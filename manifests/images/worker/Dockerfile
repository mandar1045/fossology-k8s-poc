ARG BASE_IMAGE=fossology/fossology:4.4.0
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y openssh-server && \
    mkdir -p /run/sshd /root/.ssh /home/fossy/.ssh && \
    chmod 700 /root/.ssh /home/fossy/.ssh && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/#LogLevel INFO/LogLevel VERBOSE/' /etc/ssh/sshd_config && \
    sed -i 's/#MaxStartups 10:30:100/MaxStartups 100:30:200/' /etc/ssh/sshd_config && \
    sed -i 's/#MaxSessions 10/MaxSessions 50/' /etc/ssh/sshd_config && \
    ssh-keygen -A

RUN cat <<'EOF' > /entrypoint-worker.sh
#!/bin/bash
set -euo pipefail

echo "[worker] Starting FOSSology worker entrypoint..."

if ! id -u fossy >/dev/null 2>&1; then
  groupadd -g 999 fossy 2>/dev/null || true
  useradd -m -u 999 -g 999 -s /bin/bash fossy 2>/dev/null || true
  echo "[worker] Created missing fossy user."
fi

if [ -f /run/secrets/ssh/authorized_keys ]; then
  cp /run/secrets/ssh/authorized_keys /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys

  mkdir -p /home/fossy/.ssh
  cp /run/secrets/ssh/authorized_keys /home/fossy/.ssh/authorized_keys
  chmod 700 /home/fossy/.ssh
  chmod 600 /home/fossy/.ssh/authorized_keys
  chown -R fossy:fossy /home/fossy/.ssh

  echo "[worker] SSH authorized_keys installed for root and fossy."
else
  echo "[worker] WARNING: missing /run/secrets/ssh/authorized_keys"
fi

if [ -f /usr/local/etc/fossology/Db.conf ]; then
  echo "[worker] Db.conf is present."
else
  echo "[worker] WARNING: missing /usr/local/etc/fossology/Db.conf"
fi

echo "[worker] Wrapped agents available:"
for agent in ecc copyright ipra ojo keyword nomos; do
  if [ -x "/usr/local/share/fossology/${agent}/agent/${agent}" ]; then
    echo "[worker]   - ${agent}"
  fi
done

touch /tmp/worker-agent-wrapper.log
chmod 666 /tmp/worker-agent-wrapper.log
tail -F /tmp/worker-agent-wrapper.log &

ssh-keygen -A 2>/dev/null || true

echo "[worker] Starting sshd with verbose auth logging..."
exec /usr/sbin/sshd -D -e
EOF

RUN cat <<'EOF' > /usr/local/bin/agent-wrapper.sh
#!/bin/bash
set -euo pipefail

agent_name="$1"
shift

agent_bin="$1"
shift

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
  "$agent_name" "$job_id" "$agent_bin" "${forwarded_args[*]}" >> "$log_file"
exec -a "$agent_name" "${agent_bin}" "${forwarded_args[@]}"
EOF

RUN chmod +x /entrypoint-worker.sh /usr/local/bin/agent-wrapper.sh && \
    for agent_path in /usr/local/share/fossology/*/agent/*; do \
      if [ -x "$agent_path" ] && [ -f "$agent_path" ]; then \
        agent_name="$(basename "$agent_path")"; \
        if [ "$agent_name" != "fo_scheduler" ]; then \
          mv "$agent_path" "${agent_path}.real"; \
          printf '%s\n' \
            '#!/bin/bash' \
            "exec /usr/local/bin/agent-wrapper.sh ${agent_name} ${agent_path}.real \"\$@\"" \
            > "$agent_path"; \
          chmod +x "$agent_path"; \
          ln -sf "$agent_path" "/usr/local/bin/${agent_name}" 2>/dev/null || true; \
        fi; \
      fi; \
    done

EXPOSE 22

ENTRYPOINT ["/bin/bash", "/entrypoint-worker.sh"]
