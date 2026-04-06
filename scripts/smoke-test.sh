#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FOSSOLOGY_URL="${FOSSOLOGY_URL:-http://localhost:30080/repo}"
NAMESPACE="${NAMESPACE:-fossology}"
SAMPLE_FILE="${SAMPLE_FILE:-$ROOT_DIR/test-data/sample.tar.gz}"
UPLOAD_COUNT="${UPLOAD_COUNT:-4}"
MIN_EXPECTED_WORKERS="${MIN_EXPECTED_WORKERS:-2}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Required command '$1' is not installed or not on PATH."
    exit 1
  fi
}

for tool in curl jq kubectl sort; do
  require_command "$tool"
done

echo "============================================"
echo "  FOSSology K8s PoC - Smoke Test"
echo "============================================"

echo
echo "[1/9] Waiting for FOSSology web UI at $FOSSOLOGY_URL..."
max_wait=180
elapsed=0
until curl -s -o /dev/null -w "%{http_code}" "$FOSSOLOGY_URL" 2>/dev/null | grep -qE "^(200|301|302)$"; do
  if [ "$elapsed" -ge "$max_wait" ]; then
    echo "ERROR: FOSSology did not become ready within ${max_wait}s"
    exit 1
  fi
  printf "."
  sleep 5
  elapsed=$((elapsed + 5))
done
echo
echo "[1/9] FOSSology UI is up!"

echo
echo "[2/9] Authenticating and getting API token..."
token_expire=$(date -u -d '+7 days' +%F)
token_name="poc-smoke-test-$(date +%s)"
token_response=$(curl -s -X POST "$FOSSOLOGY_URL/api/v1/tokens" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"fossy\",
    \"password\": \"fossy\",
    \"token_name\": \"${token_name}\",
    \"token_scope\": \"write\",
    \"token_expire\": \"${token_expire}\"
  }")

token=$(echo "$token_response" | jq -r '.Authorization // .authorization // ""' | sed 's/^Bearer //')
if [ -z "$token" ] || [ "$token" = "null" ]; then
  echo "ERROR: Failed to get API token. Response: $token_response"
  exit 1
fi
auth_header="Authorization: Bearer $token"
echo "[2/9] Got token: ${token:0:20}..."

echo
echo "[3/9] Verifying dynamic worker hosts..."
hosts_block=$(kubectl -n "$NAMESPACE" exec deployment/fossology-web -c fossology -- \
  sed -n '/^\[HOSTS\]/,/^\[REPOSITORY\]/p' /usr/local/etc/fossology/fossology.conf)
echo "$hosts_block"
worker_host_count=$(echo "$hosts_block" | grep -E '^fossology-workers-[0-9]+ =' | wc -l | tr -d ' ')
if [ "$worker_host_count" -lt "$MIN_EXPECTED_WORKERS" ]; then
  echo "ERROR: Expected at least $MIN_EXPECTED_WORKERS worker hosts in fossology.conf, found $worker_host_count"
  exit 1
fi
echo "[3/9] Scheduler config advertises $worker_host_count workers."

echo
echo "[4/9] Checking scheduler startup logs for invalidated worker agents..."
scheduler_logs=$(kubectl -n "$NAMESPACE" logs deployment/fossology-web -c fossology --tail=250)
invalid_agent_lines=$(echo "$scheduler_logs" | grep -E 'fossology-workers-[0-9]+\.(ecc|copyright|ipra|ojo|keyword|nomos)' || true)
if [ -n "$invalid_agent_lines" ]; then
  echo "ERROR: Worker agent startup still looks unhealthy:"
  echo "$invalid_agent_lines"
  exit 1
fi
echo "[4/9] Scheduler startup logs are clean for wrapped worker agents."

echo
echo "[5/9] Testing scheduler-style SSH access to every worker pod..."
worker_pods=$(kubectl -n "$NAMESPACE" get pods -l app=fossology-worker -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | sort)
for pod in $worker_pods; do
  fqdn="${pod}.fossology-workers.${NAMESPACE}.svc.cluster.local"
  echo "  -> $fqdn"
  kubectl -n "$NAMESPACE" exec deployment/fossology-web -c fossology -- \
    ssh -o StrictHostKeyChecking=no \
        -o ConnectTimeout=10 \
        -i /root/.ssh/id_ed25519 \
        fossy@"$fqdn" \
        "/usr/local/etc/fossology/mods-enabled/nomos/agent/nomos --scheduler_start --userID=0 --groupID=0 --jobId=0 --config=/usr/local/etc/fossology 2>&1 | head -n 3"
done
echo "[5/9] Scheduler can reach all workers."

echo
echo "[6/9] Uploading $UPLOAD_COUNT test archive(s)..."
if [ ! -f "$SAMPLE_FILE" ]; then
  echo "ERROR: $SAMPLE_FILE not found."
  exit 1
fi

declare -a upload_ids=()
declare -a job_ids=()
for index in $(seq 1 "$UPLOAD_COUNT"); do
  upload_response=$(curl -s -X POST "$FOSSOLOGY_URL/api/v1/uploads" \
    -H "$auth_header" \
    -H "folderId: 1" \
    -H "uploadDescription: k8s-poc-smoke-test-$index" \
    -H "public: public" \
    -H "uploadType: file" \
    -F "fileInput=@$SAMPLE_FILE;type=application/gzip")
  upload_id=$(echo "$upload_response" | jq -r '.message // ""' | grep -oE '[0-9]+' | head -1)
  if [ -z "$upload_id" ]; then
    echo "ERROR: Upload $index failed. Response: $upload_response"
    exit 1
  fi
  upload_ids+=("$upload_id")
  echo "  -> upload $index queued with upload ID $upload_id"
done

echo
echo "[7/9] Waiting for uploads to unpack..."
sleep 15

echo
echo "[8/9] Triggering concurrent nomos scans..."
for upload_id in "${upload_ids[@]}"; do
  job_response=$(curl -s -X POST "$FOSSOLOGY_URL/api/v1/jobs" \
    -H "$auth_header" \
    -H "folderId: 1" \
    -H "uploadId: $upload_id" \
    -H "Content-Type: application/json" \
    -d '{"analysis":{"nomos":true},"decider":{},"reuse":{}}')
  job_id=$(echo "$job_response" | jq -r '.message // ""' | grep -oE '[0-9]+' | head -1)
  if [ -z "$job_id" ]; then
    echo "ERROR: Failed to queue job for upload $upload_id. Response: $job_response"
    exit 1
  fi
  job_ids+=("$job_id")
  echo "  -> upload $upload_id queued as job $job_id"
done

echo
echo "[9/9] Waiting for all scans to complete and verifying worker distribution..."
all_completed=0
for attempt in $(seq 1 60); do
  completed_count=0
  for upload_id in "${upload_ids[@]}"; do
    status=$(curl -s "$FOSSOLOGY_URL/api/v1/jobs?upload=$upload_id" \
      -H "$auth_header" | jq -r '.[0].status // "unknown"' 2>/dev/null || echo "unknown")
    printf "  -> upload %s status after %ss: %s\n" "$upload_id" "$((attempt * 5))" "$status"
    if [ "$status" = "Completed" ]; then
      completed_count=$((completed_count + 1))
    fi
  done
  if [ "$completed_count" -eq "${#upload_ids[@]}" ]; then
    all_completed=1
    break
  fi
  sleep 5
done

if [ "$all_completed" -ne 1 ]; then
  echo "ERROR: Not all scans completed within 5 minutes."
  exit 1
fi

echo
echo "=== Web container logs (scheduler + bootstrap) ==="
kubectl -n "$NAMESPACE" logs deployment/fossology-web -c fossology --tail=160 | \
  grep -iE 'scheduler|host|ssh|agent|dispatch' || true

echo
echo "=== Config-sync sidecar logs ==="
kubectl -n "$NAMESPACE" logs deployment/fossology-web -c config-sync --tail=120 || true

echo
echo "=== Worker logs ==="
workers_with_nomos=0
for pod in $worker_pods; do
  echo "--- $pod ---"
  pod_logs=$(kubectl -n "$NAMESPACE" logs "$pod" --tail=240 || true)
  echo "$pod_logs" | grep -E 'Accepted publickey|worker-agent-wrapper|dropping duplicate' || true
  if echo "$pod_logs" | grep -q '\[worker-agent-wrapper\] agent=nomos job_id='; then
    workers_with_nomos=$((workers_with_nomos + 1))
  fi
done

if [ "$workers_with_nomos" -lt "$MIN_EXPECTED_WORKERS" ]; then
  echo
  echo "ERROR: Expected nomos execution traces on at least $MIN_EXPECTED_WORKERS workers, found $workers_with_nomos."
  exit 1
fi

echo
echo "Verified nomos execution traces on $workers_with_nomos worker pods."

echo
echo "============================================"
echo "  SMOKE TEST COMPLETE"
echo "============================================"
echo
echo "  FOSSology UI: http://localhost:30080/repo"
echo "  Upload IDs:   ${upload_ids[*]}"
echo "  Job IDs:      ${job_ids[*]}"
echo
