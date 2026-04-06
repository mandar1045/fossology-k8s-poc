#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELM_IMAGE="${HELM_IMAGE:-alpine/helm:3.17.3}"

if command -v helm >/dev/null 2>&1; then
  exec helm "$@"
fi

exec docker run --rm -v "$ROOT_DIR:/work" -w /work "$HELM_IMAGE" "$@"
