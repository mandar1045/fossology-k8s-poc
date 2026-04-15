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

COPY manifests/images/worker/entrypoint.sh /entrypoint-worker.sh
COPY manifests/images/worker/agent-wrapper.sh /usr/local/bin/agent-wrapper.sh

RUN chmod +x /entrypoint-worker.sh /usr/local/bin/agent-wrapper.sh && \
    for agent_path in /usr/local/share/fossology/*/agent/*; do \
      if [ ! -x "$agent_path" ]; then \
        continue; \
      fi; \
      agent_name="$(basename "$agent_path")"; \
      if [ "$agent_name" = "fo_scheduler" ]; then \
        continue; \
      fi; \
      if [ -L "$agent_path" ]; then \
        ln -sf "$agent_path" "/usr/local/bin/${agent_name}" 2>/dev/null || true; \
        continue; \
      fi; \
      if [ ! -f "$agent_path" ]; then \
        continue; \
      fi; \
      agent_magic="$(head -c 4 "$agent_path" | od -An -tx1 | tr -d ' \n')"; \
      if [ "$agent_magic" != "7f454c46" ]; then \
        ln -sf "$agent_path" "/usr/local/bin/${agent_name}" 2>/dev/null || true; \
        continue; \
      fi; \
      mv "$agent_path" "${agent_path}.real"; \
      printf '%s\n' \
        '#!/bin/bash' \
        "exec /usr/local/bin/agent-wrapper.sh ${agent_name} ${agent_path}.real \"\$@\"" \
        > "$agent_path"; \
      chmod +x "$agent_path"; \
      ln -sf "$agent_path" "/usr/local/bin/${agent_name}" 2>/dev/null || true; \
    done

EXPOSE 22

ENTRYPOINT ["/bin/bash", "/entrypoint-worker.sh"]
