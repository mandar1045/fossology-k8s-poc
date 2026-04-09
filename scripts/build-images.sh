#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

DEFAULT_SOURCE_REPO="$ROOT_DIR/../fossology-gsoc/fossology"
BUILD_FOSSOLOGY_FROM_SOURCE="${BUILD_FOSSOLOGY_FROM_SOURCE:-0}"
FOSSOLOGY_REPO_DIR="${FOSSOLOGY_REPO_DIR:-}"
FOSSOLOGY_IMAGE="${FOSSOLOGY_IMAGE:-}"
WORKER_IMAGE="${WORKER_IMAGE:-}"
IMAGE_ENV_FILE="${IMAGE_ENV_FILE:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command '$1' is not installed or not on PATH."
    exit 1
  fi
}

slugify() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's#[^a-z0-9_.-]#-#g'
}

ensure_source_repo() {
  if [ -n "$FOSSOLOGY_REPO_DIR" ]; then
    return 0
  fi

  if [ -d "$DEFAULT_SOURCE_REPO/.git" ]; then
    FOSSOLOGY_REPO_DIR="$DEFAULT_SOURCE_REPO"
    return 0
  fi

  echo "ERROR: BUILD_FOSSOLOGY_FROM_SOURCE is enabled, but no source repo was found."
  echo "       Set FOSSOLOGY_REPO_DIR=/absolute/path/to/fossology."
  exit 1
}

infer_source_image() {
  local branch_slug commit_sha

  branch_slug="$(git -C "$FOSSOLOGY_REPO_DIR" branch --show-current 2>/dev/null || true)"
  if [ -z "$branch_slug" ]; then
    branch_slug="detached-head"
  fi
  branch_slug="$(slugify "$branch_slug")"

  commit_sha="$(git -C "$FOSSOLOGY_REPO_DIR" rev-parse --short HEAD)"

  if [ -z "$FOSSOLOGY_IMAGE" ] || [ "$FOSSOLOGY_IMAGE" = "fossology/fossology:4.4.0" ]; then
    FOSSOLOGY_IMAGE="fossology-branch:${branch_slug}-${commit_sha}"
  fi

  if [ -z "$WORKER_IMAGE" ] || [ "$WORKER_IMAGE" = "fossology-worker:poc" ]; then
    WORKER_IMAGE="fossology-worker:${branch_slug}-${commit_sha}"
  fi
}

build_source_image() {
  local current_branch commit_sha

  current_branch="$(git -C "$FOSSOLOGY_REPO_DIR" branch --show-current 2>/dev/null || true)"
  if [ -z "$current_branch" ]; then
    current_branch="detached-head"
  fi
  commit_sha="$(git -C "$FOSSOLOGY_REPO_DIR" rev-parse --short HEAD)"

  echo "[build] Building FOSSology source image from:"
  echo "        repo:   $FOSSOLOGY_REPO_DIR"
  echo "        branch: $current_branch"
  echo "        commit: $commit_sha"
  echo "        image:  $FOSSOLOGY_IMAGE"
  docker build -t "$FOSSOLOGY_IMAGE" "$FOSSOLOGY_REPO_DIR"
}

build_worker_image() {
  local build_args=()

  if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ]; then
    build_args+=(--build-arg "BASE_IMAGE=$FOSSOLOGY_IMAGE")
  fi

  echo "[build] Building worker image:"
  echo "        image: $WORKER_IMAGE"
  if [ ${#build_args[@]} -gt 0 ]; then
    echo "        base:  $FOSSOLOGY_IMAGE"
  fi
  docker build "${build_args[@]}" -t "$WORKER_IMAGE" \
    -f "$ROOT_DIR/manifests/images/worker/Dockerfile" \
    "$ROOT_DIR"
}

require_command docker

if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ]; then
  require_command git
  ensure_source_repo
  infer_source_image
  build_source_image
fi

if [ -z "$WORKER_IMAGE" ]; then
  WORKER_IMAGE="fossology-worker:poc"
fi

build_worker_image

if [ -n "$IMAGE_ENV_FILE" ]; then
  cat > "$IMAGE_ENV_FILE" <<EOF
FOSSOLOGY_IMAGE=$FOSSOLOGY_IMAGE
WORKER_IMAGE=$WORKER_IMAGE
EOF
fi

echo
echo "FOSSOLOGY_IMAGE=$FOSSOLOGY_IMAGE"
echo "WORKER_IMAGE=$WORKER_IMAGE"
