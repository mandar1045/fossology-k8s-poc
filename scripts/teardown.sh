#!/bin/bash
set -euo pipefail

KIND_CLUSTER="${KIND_CLUSTER:-fossology-poc}"

echo "[teardown] Deleting kind cluster '${KIND_CLUSTER}'..."
if ! cluster_list="$(kind get clusters 2>&1)"; then
  echo "[teardown] Unable to query kind clusters:"
  echo "$cluster_list"
  exit 1
fi

if printf '%s\n' "$cluster_list" | grep -qx "$KIND_CLUSTER"; then
  kind delete cluster --name "$KIND_CLUSTER"
else
  echo "[teardown] Cluster not found, skipping."
fi

echo "[teardown] Cleaning up local secrets (not SSH keys)..."
# Keep the SSH keys in secrets/ for reproducibility
# Remove only the generated k8s manifests if any

echo "[teardown] Done."
