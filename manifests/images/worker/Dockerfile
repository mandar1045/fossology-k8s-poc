FROM fossology/fossology:4.4.0

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
    for agent in ecc copyright ipra ojo keyword nomos; do \
      mv "/usr/local/share/fossology/${agent}/agent/${agent}" "/usr/local/share/fossology/${agent}/agent/${agent}.real"; \
      printf '%s\n' \
        '#!/bin/bash' \
        "exec /usr/local/bin/agent-wrapper.sh ${agent} /usr/local/share/fossology/${agent}/agent/${agent}.real \"\$@\"" \
        > "/usr/local/share/fossology/${agent}/agent/${agent}"; \
      chmod +x "/usr/local/share/fossology/${agent}/agent/${agent}"; \
    done && \
    for agent in ecc copyright ipra ojo keyword nomos; do \
      ln -sf "/usr/local/share/fossology/${agent}/agent/${agent}" "/usr/local/bin/${agent}"; \
    done

EXPOSE 22

ENTRYPOINT ["/entrypoint-worker.sh"]
