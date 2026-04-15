#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_SOURCE_REPO="$ROOT_DIR/fossology-gsoc/fossology"
DEFAULT_NESTED_CHART="$DEFAULT_SOURCE_REPO/deploy/helm/fossology"
DEFAULT_ROOT_CHART="$ROOT_DIR/deploy/helm/fossology"

RUN_TESTS=0

usage() {
  cat <<'EOF'
Usage: bash scripts/run-updated-poc.sh [options]

Deploy the updated Helm-based FOSSology PoC using the existing setup flow.

Options:
  --test                 Run the smoke test after deployment
  --from-source          Build the web image from the local FOSSology checkout
  --chart <path>         Override the Helm chart path
  --values <path>        Override the Helm values file
  --release <name>       Override the Helm release name
  --namespace <name>     Override the Kubernetes namespace
  --skip-image-build     Reuse existing images instead of rebuilding
  -h, --help             Show this help message

Environment overrides:
  HELM_CHART, HELM_VALUES, HELM_RELEASE, NAMESPACE,
  BUILD_FOSSOLOGY_FROM_SOURCE, FOSSOLOGY_REPO_DIR,
  FOSSOLOGY_IMAGE, WORKER_IMAGE, SKIP_IMAGE_BUILD
EOF
}

if [ -d "$DEFAULT_NESTED_CHART" ]; then
  DEFAULT_HELM_CHART="$DEFAULT_NESTED_CHART"
else
  DEFAULT_HELM_CHART="$DEFAULT_ROOT_CHART"
fi

if [ -f "$DEFAULT_HELM_CHART/values-local.yaml" ]; then
  DEFAULT_HELM_VALUES="$DEFAULT_HELM_CHART/values-local.yaml"
else
  DEFAULT_HELM_VALUES="$DEFAULT_HELM_CHART/values.yaml"
fi

HELM_CHART="${HELM_CHART:-$DEFAULT_HELM_CHART}"
HELM_VALUES="${HELM_VALUES:-$DEFAULT_HELM_VALUES}"
HELM_RELEASE="${HELM_RELEASE:-fossology}"
NAMESPACE="${NAMESPACE:-fossology}"
BUILD_FOSSOLOGY_FROM_SOURCE="${BUILD_FOSSOLOGY_FROM_SOURCE:-0}"
FOSSOLOGY_REPO_DIR="${FOSSOLOGY_REPO_DIR:-$DEFAULT_SOURCE_REPO}"
SKIP_IMAGE_BUILD="${SKIP_IMAGE_BUILD:-0}"

while [ $# -gt 0 ]; do
  case "$1" in
    --test)
      RUN_TESTS=1
      shift
      ;;
    --from-source)
      BUILD_FOSSOLOGY_FROM_SOURCE=1
      shift
      ;;
    --chart)
      HELM_CHART="$2"
      shift 2
      ;;
    --values)
      HELM_VALUES="$2"
      shift 2
      ;;
    --release)
      HELM_RELEASE="$2"
      shift 2
      ;;
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --skip-image-build)
      SKIP_IMAGE_BUILD=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option '$1'"
      echo
      usage
      exit 1
      ;;
  esac
done

if [ ! -d "$HELM_CHART" ]; then
  echo "ERROR: Helm chart path not found: $HELM_CHART"
  exit 1
fi

if [ ! -f "$HELM_VALUES" ]; then
  echo "ERROR: Helm values file not found: $HELM_VALUES"
  exit 1
fi

if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ] && [ ! -d "$FOSSOLOGY_REPO_DIR/.git" ]; then
  echo "ERROR: --from-source was requested, but no FOSSology git checkout was found at:"
  echo "       $FOSSOLOGY_REPO_DIR"
  exit 1
fi

echo "============================================"
echo "  Run Updated FOSSology PoC"
echo "============================================"
echo
echo "  Chart:       $HELM_CHART"
echo "  Values:      $HELM_VALUES"
echo "  Release:     $HELM_RELEASE"
echo "  Namespace:   $NAMESPACE"
echo "  From source: $BUILD_FOSSOLOGY_FROM_SOURCE"
if [ "$BUILD_FOSSOLOGY_FROM_SOURCE" = "1" ]; then
  echo "  Source repo: $FOSSOLOGY_REPO_DIR"
fi
echo "  Smoke test:  $RUN_TESTS"
echo

DEPLOY_MODE=helm \
HELM_CHART="$HELM_CHART" \
HELM_VALUES="$HELM_VALUES" \
HELM_RELEASE="$HELM_RELEASE" \
NAMESPACE="$NAMESPACE" \
BUILD_FOSSOLOGY_FROM_SOURCE="$BUILD_FOSSOLOGY_FROM_SOURCE" \
FOSSOLOGY_REPO_DIR="$FOSSOLOGY_REPO_DIR" \
SKIP_IMAGE_BUILD="$SKIP_IMAGE_BUILD" \
bash "$SCRIPT_DIR/setup.sh"

if [ "$RUN_TESTS" = "1" ]; then
  echo
  echo "Running smoke test..."
  NAMESPACE="$NAMESPACE" bash "$SCRIPT_DIR/smoke-test.sh"
fi
