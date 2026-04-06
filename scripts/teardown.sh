#!/bin/bash
set -euo pipefail

KIND_CLUSTER="${KIND_CLUSTER:-fossology-poc}"

echo "[teardown] Deleting kind cluster '${KIND_CLUSTER}'..."
kind delete cluster --name "$KIND_CLUSTER" 2>/dev/null || echo "[teardown] Cluster not found, skipping."

echo "[teardown] Cleaning up local secrets (not SSH keys)..."
# Keep the SSH keys in secrets/ for reproducibility
# Remove only the generated k8s manifests if any

echo "[teardown] Done."
