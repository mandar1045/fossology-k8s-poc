#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_CLUSTER="${KIND_CLUSTER:-fossology-poc}"
WORKER_IMAGE="${WORKER_IMAGE:-fossology-worker:poc}"
KIND_CONFIG="${KIND_CONFIG:-$ROOT_DIR/manifests/kind/kind-config.yaml}"
NAMESPACE="${NAMESPACE:-fossology}"
DEPLOY_MODE="${DEPLOY_MODE:-raw}"
HELM_RELEASE="${HELM_RELEASE:-fossology}"
HELM_CHART="${HELM_CHART:-deploy/helm/fossology}"
HELM_VALUES="${HELM_VALUES:-$HELM_CHART/values.yaml}"

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

for tool in docker kind kubectl ssh-keygen; do
  require_command "$tool"
done

echo "============================================"
echo "  FOSSology Kubernetes PoC - Full Setup"
echo "============================================"

echo
echo "[1/8] Building worker Docker image..."
docker build -t "$WORKER_IMAGE" -f "$ROOT_DIR/manifests/images/worker/Dockerfile" "$ROOT_DIR"
echo "      Worker image built."

echo
echo "[2/8] Creating kind cluster '$KIND_CLUSTER'..."
if kind get clusters | grep -q "^${KIND_CLUSTER}$"; then
  echo "      Cluster already exists, skipping."
else
  kind create cluster --config "$KIND_CONFIG" --name "$KIND_CLUSTER"
  echo "      Cluster created."
fi

echo
echo "[3/8] Loading worker image into kind cluster..."
kind load docker-image "$WORKER_IMAGE" --name "$KIND_CLUSTER"
echo "      Image loaded."

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
  kubectl apply -f "$ROOT_DIR/manifests/serviceaccount-web.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/role-config-sync.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/secret-db.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/pvc-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/pvc-repo.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/statefulset-postgres.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-workers.yaml"
  apply_or_recreate_statefulset "fossology-workers" "$ROOT_DIR/manifests/statefulset-workers.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/deployment-web.yaml"
  kubectl apply -f "$ROOT_DIR/manifests/service-web.yaml"
else
  (
    cd "$ROOT_DIR"
    bash "$SCRIPT_DIR/run-helm.sh" upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
      --namespace "$NAMESPACE" \
      --create-namespace \
      -f "$HELM_VALUES"
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
