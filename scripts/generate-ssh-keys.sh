#!/bin/bash
set -euo pipefail

SECRETS_DIR="$(cd "$(dirname "$0")/.." && pwd)/secrets"
NAMESPACE="${NAMESPACE:-fossology}"
mkdir -p "$SECRETS_DIR"

KEY_FILE="$SECRETS_DIR/id_ed25519"

if [ -f "$KEY_FILE" ]; then
    echo "[ssh-keygen] SSH key already exists at $KEY_FILE, skipping generation."
else
    echo "[ssh-keygen] Generating Ed25519 SSH keypair..."
    ssh-keygen -t ed25519 -N "" -C "fossology-scheduler" -f "$KEY_FILE"
    echo "[ssh-keygen] Keypair generated."
fi

echo "[ssh-keygen] Creating Kubernetes secrets..."

# Delete existing secrets if they exist
kubectl delete secret fossology-ssh-private fossology-ssh-public \
    -n "$NAMESPACE" --ignore-not-found=true

# Create private key secret (for scheduler/web pod)
kubectl create secret generic fossology-ssh-private \
    --from-file=id_ed25519="$KEY_FILE" \
    -n "$NAMESPACE"

# Create public key secret as authorized_keys (for worker pods)
kubectl create secret generic fossology-ssh-public \
    --from-file=authorized_keys="${KEY_FILE}.pub" \
    -n "$NAMESPACE"

echo "[ssh-keygen] Kubernetes SSH secrets created."
echo "  fossology-ssh-private  -> scheduler mounts id_ed25519"
echo "  fossology-ssh-public   -> worker mounts authorized_keys"
