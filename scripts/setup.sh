#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_CLUSTER="${KIND_CLUSTER:-fossology-poc}"
FOSSOLOGY_IMAGE="${FOSSOLOGY_IMAGE:-fossology/fossology:4.4.0}"
WORKER_IMAGE="${WORKER_IMAGE:-fossology-worker:poc}"
BUILD_FOSSOLOGY_FROM_SOURCE="${BUILD_FOSSOLOGY_FROM_SOURCE:-0}"
SKIP_IMAGE_BUILD="${SKIP_IMAGE_BUILD:-0}"
FOSSOLOGY_REPO_DIR="${FOSSOLOGY_REPO_DIR:-}"
KIND_CONFIG="${KIND_CONFIG:-$ROOT_DIR/manifests/kind/kind-config.yaml}"
NAMESPACE="${NAMESPACE:-fossology}"
DEPLOY_MODE="${DEPLOY_MODE:-raw}"
HELM_RELEASE="${HELM_RELEASE:-fossology}"
HELM_CHART="${HELM_CHART:-deploy/helm/fossology}"
HELM_VALUES="${HELM_VALUES:-$HELM_CHART/values.yaml}"
RENDERED_MANIFEST_DIR=""
IMAGE_ENV_FILE=""

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command '$1' is not installed or not on PATH."
    exit 1
  fi
}

apply_or_recreate_statefulset() {
  local name="$1"
  local manifest="$2"

  if kubectl apply -f "$manifest"; then
    return 0
  fi

  echo "      StatefulSet '$name' requires recreation because an immutable field changed."
  kubectl delete statefulset "$name" -n "$NAMESPACE" --wait=true
  kubectl apply -f "$manifest"
}

cleanup() {
  if [ -n "$RENDERED_MANIFEST_DIR" ] && [ -d "$RENDERED_MANIFEST_DIR" ]; then
    rm -rf "$RENDERED_MANIFEST_DIR"
  fi
  if [ -n "$IMAGE_ENV_FILE" ] && [ -f "$IMAGE_ENV_FILE" ]; then
    rm -f "$IMAGE_ENV_FILE"
  fi
}

render_manifest_with_images() {
  local source_manifest="$1"
  local rendered_manifest="$2"

  sed \
    -e "s|fossology/fossology:4.4.0|$FOSSOLOGY_IMAGE|g" \
    -e "s|fossology-worker:poc|$WORKER_IMAGE|g" \
    "$source_manifest" > "$rendered_manifest"
}

image_repo() {
  local image_ref="$1"
  echo "${image_ref%:*}"
}

image_tag() {
  local image_ref="$1"
  local last_segment="${image_ref##*/}"

  if [[ "$last_segment" == *:* ]]; then
    echo "${image_ref##*:}"
  else
    echo "latest"
  fi
}

trap cleanup EXIT

for tool in docker kind kubectl ssh-keygen; do
  require_command "$tool"
done

echo "============================================"
echo "  FOSSology Kubernetes PoC - Full Setup"
echo "============================================"

echo
echo "[1/8] Building worker Docker image..."
if [ "$SKIP_IMAGE_BUILD" = "1" ]; then
  echo "      Skipping image build and reusing:"
  echo "        web:    $FOSSOLOGY_IMAGE"
  echo "        worker: $WORKER_IMAGE"
else
  if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ]; then
    require_command git
    echo "      Building source-backed web + worker images..."
  else
    echo "      Building worker image..."
  fi

  IMAGE_ENV_FILE="$(mktemp /tmp/fossology-k8s-poc-images.XXXXXX)"
  BUILD_FOSSOLOGY_FROM_SOURCE="$BUILD_FOSSOLOGY_FROM_SOURCE" \
  FOSSOLOGY_REPO_DIR="$FOSSOLOGY_REPO_DIR" \
  FOSSOLOGY_IMAGE="$FOSSOLOGY_IMAGE" \
  WORKER_IMAGE="$WORKER_IMAGE" \
  IMAGE_ENV_FILE="$IMAGE_ENV_FILE" \
  bash "$SCRIPT_DIR/build-images.sh"
  # shellcheck disable=SC1090
  source "$IMAGE_ENV_FILE"
  echo "      Images ready."
fi

echo
echo "[2/8] Creating kind cluster '$KIND_CLUSTER'..."
if kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
  echo "      Cluster already exists, skipping."
else
  kind create cluster --config "$KIND_CONFIG" --name "$KIND_CLUSTER"
  echo "      Cluster created."
fi

echo
echo "[3/8] Loading images into kind cluster..."
if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ]; then
  kind load docker-image "$FOSSOLOGY_IMAGE" --name "$KIND_CLUSTER"
  echo "      Loaded web image: $FOSSOLOGY_IMAGE"
fi
kind load docker-image "$WORKER_IMAGE" --name "$KIND_CLUSTER"
echo "      Loaded worker image: $WORKER_IMAGE"

echo
echo "[4/8] Creating namespace..."
kubectl apply -f "$ROOT_DIR/manifests/namespace.yaml"

echo
echo "[5/8] Generating SSH keys and Kubernetes secrets..."
bash "$SCRIPT_DIR/generate-ssh-keys.sh"

echo
echo "[6/8] Creating generated runtime ConfigMap..."
if [ "$DEPLOY_MODE" = "raw" ]; then
  kubectl create configmap fossology-runtime-config \
    --namespace "$NAMESPACE" \
    --from-file=fossology.conf.tmpl="$ROOT_DIR/manifests/templates/fossology.conf.tmpl" \
    --from-file=render_fossology_conf.py="$ROOT_DIR/scripts/render_fossology_conf.py" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "      Runtime ConfigMap applied."
else
  echo "      Helm chart manages runtime config; skipping raw ConfigMap bootstrap."
fi

echo
echo "[7/8] Applying Kubernetes manifests..."
if [ "$DEPLOY_MODE" = "raw" ]; then
  RENDERED_MANIFEST_DIR="$(mktemp -d /tmp/fossology-k8s-poc-manifests.XXXXXX)"
  render_manifest_with_images "$ROOT_DIR/manifests/statefulset-workers.yaml" "$RENDERED_MANIFEST_DIR/statefulset-workers.yaml"
  render_manifest_with_images "$ROOT_DIR/manifests/deployment-web.yaml" "$RENDERED_MANIFEST_DIR/deployment-web.yaml"

  kubectl apply -f "$ROOT_DIR/manifests/serviceaccount-web.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/role-config-sync.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/secret-db.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/pvc-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/pvc-repo.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/statefulset-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-workers.yaml"
  apply_or_recreate_statefulset "fossology-workers" "$RENDERED_MANIFEST_DIR/statefulset-workers.yaml"
  kubectl apply -f "$RENDERED_MANIFEST_DIR/deployment-web.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-web.yaml"
else
  (
    cd "$ROOT_DIR"
    bash "$SCRIPT_DIR/run-helm.sh" upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
      --namespace "$NAMESPACE" \
      --create-namespace \
      -f "$HELM_VALUES" \
      --set-string images.web.repository="$(image_repo "$FOSSOLOGY_IMAGE")" \
      --set-string images.web.tag="$(image_tag "$FOSSOLOGY_IMAGE")" \
      --set-string images.worker.repository="$(image_repo "$WORKER_IMAGE")" \
      --set-string images.worker.tag="$(image_tag "$WORKER_IMAGE")"
  )
fi
echo "      Manifests applied."

echo
echo "[8/8] Waiting for all pods to be ready..."
bash "$SCRIPT_DIR/wait-for-ready.sh"

echo
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo
echo "  FOSSology UI:  http://localhost:30080/repo"
echo "  Login:         fossy / fossy"
echo
echo "  Run the smoke test:"
echo "    make test"
echo
