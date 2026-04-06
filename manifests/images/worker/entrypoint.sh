#!/bin/bash
set -euo pipefail

echo "[worker] Starting FOSSology worker entrypoint..."

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
