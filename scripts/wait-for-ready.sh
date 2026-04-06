#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-fossology}"
TIMEOUT="${TIMEOUT:-300}"

echo "[wait] Waiting for PostgreSQL to be ready..."
kubectl rollout status statefulset/fossology-db -n "$NAMESPACE" --timeout="${TIMEOUT}s"
echo "[wait] PostgreSQL is ready."

echo "[wait] Waiting for worker pods to be ready..."
kubectl rollout status statefulset/fossology-workers -n "$NAMESPACE" --timeout="${TIMEOUT}s"
echo "[wait] Worker StatefulSet is ready."

echo "[wait] Waiting for web deployment to be ready..."
kubectl rollout status deployment/fossology-web -n "$NAMESPACE" --timeout="${TIMEOUT}s"
echo "[wait] Web deployment is ready."

echo
echo "[wait] Current pod state:"
kubectl get pods -n "$NAMESPACE" -o wide
