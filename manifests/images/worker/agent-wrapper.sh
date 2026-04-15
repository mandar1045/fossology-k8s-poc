#!/bin/bash
set -euo pipefail

agent_name="${1:?missing agent name}"
real_bin="${2:?missing real binary path}"
shift 2
log_file="/tmp/worker-agent-wrapper.log"

declare -a forwarded_args=()
seen_scheduler_start=0
job_id="unknown"

for arg in "$@"; do
  if [[ "$arg" == "--scheduler_start" ]]; then
    if (( seen_scheduler_start )); then
      printf '[worker-agent-wrapper] agent=%s dropping duplicate --scheduler_start\n' \
        "$agent_name" >> "$log_file"
      continue
    fi
    seen_scheduler_start=1
  fi
  if [[ "$arg" == --jobId=* ]]; then
    job_id="${arg#--jobId=}"
  fi
  forwarded_args+=("$arg")
done

if (( seen_scheduler_start )); then
  sleep_time=$(( RANDOM % 10 + 1 ))
  printf '[worker-agent-wrapper] agent=%s splaying startup by %ds\n' "$agent_name" "$sleep_time" >> "$log_file"
  sleep "$sleep_time"
fi

printf '[worker-agent-wrapper] agent=%s job_id=%s exec=%s args=%s\n' \
  "$agent_name" "$job_id" "$real_bin" "${forwarded_args[*]}" >> "$log_file"
exec -a "$agent_name" "${real_bin}" "${forwarded_args[@]}"
