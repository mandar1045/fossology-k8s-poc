#!/bin/bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-fossology}"
CONTROL_PLANE_CONTAINER="${CONTROL_PLANE_CONTAINER:-fossology-poc-control-plane}"
WEB_DEPLOYMENT="${WEB_DEPLOYMENT:-deployment/fossology-web}"
WORKER_LABEL="${WORKER_LABEL:-app=fossology-worker}"
WORKER_FQDN="${WORKER_FQDN:-fossology-workers-0.fossology-workers.fossology.svc.cluster.local}"
OUTPUT_DIR="${OUTPUT_DIR:-/tmp/fossology-k8s-poc-artifacts}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_FILE="${OUTPUT_DIR}/poc-proof-${TIMESTAMP}.log"

mkdir -p "${OUTPUT_DIR}"

if [ -n "${KUBECTL_CMD:-}" ]; then
  # shellcheck disable=SC2206
  KUBECTL_BIN=(${KUBECTL_CMD})
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_BIN=(kubectl)
elif command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "${CONTROL_PLANE_CONTAINER}"; then
  KUBECTL_BIN=(docker exec "${CONTROL_PLANE_CONTAINER}" kubectl)
else
  echo "ERROR: Neither kubectl nor docker-exec access to ${CONTROL_PLANE_CONTAINER} is available."
  exit 1
fi

run_kubectl() {
  "${KUBECTL_BIN[@]}" "$@"
}

section() {
  printf '\n============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

run_cmd() {
  local title="$1"
  shift
  section "$title"
  printf '$ %s\n\n' "$*"
  "$@"
}

exec > >(tee "${OUTPUT_FILE}") 2>&1

section "FOSSology Kubernetes PoC Proof Capture"
printf 'Timestamp: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z (%z)')"
printf 'Namespace: %s\n' "${NAMESPACE}"
printf 'Worker FQDN: %s\n' "${WORKER_FQDN}"
printf 'Log file: %s\n' "${OUTPUT_FILE}"

run_cmd "1. Pod Overview" \
  run_kubectl -n "${NAMESPACE}" get pods -o wide

run_cmd "2. Service Overview" \
  run_kubectl -n "${NAMESPACE}" get svc

run_cmd "3. Web Pod Processes (Apache + fo_scheduler)" \
  run_kubectl -n "${NAMESPACE}" exec "${WEB_DEPLOYMENT}" -c fossology -- \
  bash -lc 'ps -ef | grep -E "fo_scheduler|apache2" | grep -v grep'

run_cmd "4. [HOSTS] Entry From fossology.conf" \
  run_kubectl -n "${NAMESPACE}" exec "${WEB_DEPLOYMENT}" -c fossology -- \
  bash -lc 'sed -n "/^\[HOSTS\]/,/^\[REPOSITORY\]/p" /usr/local/etc/fossology/fossology.conf'

run_cmd "5. DNS Resolution From Web Pod To Worker" \
  run_kubectl -n "${NAMESPACE}" exec "${WEB_DEPLOYMENT}" -c fossology -- \
  bash -lc "getent hosts ${WORKER_FQDN}"

run_cmd "6. SSH From Web Pod To Worker + nomos Handshake" \
  run_kubectl -n "${NAMESPACE}" exec "${WEB_DEPLOYMENT}" -c fossology -- \
  bash -lc "ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i /root/.ssh/id_ed25519 fossy@${WORKER_FQDN} '/usr/local/etc/fossology/mods-enabled/nomos/agent/nomos --scheduler_start --userID=0 --groupID=0 --jobId=0 --config=/usr/local/etc/fossology 2>&1 | head -n 4'"

run_cmd "7. Shared Repository Visible In Web Pod" \
  run_kubectl -n "${NAMESPACE}" exec "${WEB_DEPLOYMENT}" -c fossology -- \
  bash -lc 'ls -ld /srv/fossology/repository && find /srv/fossology/repository -maxdepth 2 | head -n 10'

run_cmd "8. Worker Pod Logs" \
  run_kubectl -n "${NAMESPACE}" logs -l "${WORKER_LABEL}" --tail=120 --prefix

run_cmd "9. Config-Sync Logs" \
  run_kubectl -n "${NAMESPACE}" logs deployment/fossology-web -c config-sync --tail=120

section "Done"
printf 'Saved proof log to: %s\n' "${OUTPUT_FILE}"
