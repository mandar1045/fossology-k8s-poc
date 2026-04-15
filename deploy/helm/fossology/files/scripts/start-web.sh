#!/bin/bash
set -euo pipefail

echo "[web] Setting up SSH client..."
if ! id -u fossy >/dev/null 2>&1; then
  groupadd -g 999 fossy 2>/dev/null || true
  useradd -m -u 999 -g 999 -s /bin/bash fossy 2>/dev/null || true
  echo "[web] Created missing fossy user."
fi
mkdir -p /root/.ssh /home/fossy/.ssh
cp /run/secrets/ssh-private/id_ed25519 /root/.ssh/id_ed25519
cp /run/secrets/ssh-private/id_ed25519 /home/fossy/.ssh/id_ed25519
chmod 600 /root/.ssh/id_ed25519 /home/fossy/.ssh/id_ed25519
printf 'Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n  IdentityFile /root/.ssh/id_ed25519\n' > /root/.ssh/config
printf 'Host *\n  StrictHostKeyChecking no\n  UserKnownHostsFile /dev/null\n  LogLevel ERROR\n  IdentityFile /home/fossy/.ssh/id_ed25519\n' > /home/fossy/.ssh/config
chmod 600 /root/.ssh/config /home/fossy/.ssh/config
chown -R fossy:fossy /home/fossy/.ssh

echo "[web] Scheduler will bind to pod IP: ${MY_POD_IP}"
chmod 644 /usr/local/etc/fossology/fossology.conf || true
echo "[web] Active worker hosts:"
sed -n '/^\[HOSTS\]/,/^\[REPOSITORY\]/p' /usr/local/etc/fossology/fossology.conf

export FOSSOLOGY_SCHEDULER_HOST="${MY_POD_IP}"
exec /fossology/docker-entrypoint.sh
