#!/bin/bash
# Railway entrypoint for the GitLab Omnibus image.
#
# Railway gives a service exactly one volume. It is mounted at /var/opt/gitlab
# (repositories, PostgreSQL, Redis, uploads). /etc/gitlab holds the other state
# GitLab cannot lose: gitlab-secrets.json (keys that decrypt CI variables, 2FA
# secrets, runner tokens) and the SSH host keys. It is moved onto the same volume
# and symlinked back, so redeploys keep it. Then the image's own init runs.
set -euo pipefail

DATA_DIR=/var/opt/gitlab
CONFIG_DIR="${DATA_DIR}/railway-etc-gitlab"

log() { echo "[railway] $*"; }

mkdir -p "$DATA_DIR"
# ext4 volumes come with lost+found at the root; GitLab does not need it.
rm -rf "${DATA_DIR}/lost+found"

mkdir -p "$CONFIG_DIR"
chmod 0775 "$CONFIG_DIR"

if [ -L /etc/gitlab ]; then
  log "/etc/gitlab -> $(readlink /etc/gitlab)"
elif mountpoint -q /etc/gitlab; then
  # Not Railway (e.g. plain `docker run`, which creates an anonymous volume for the
  # image's VOLUME /etc/gitlab). Keep using that mount.
  log "WARNING: /etc/gitlab is a separate mount; it is NOT stored in ${DATA_DIR}."
else
  # First boot on this container: keep anything the image put there, never
  # overwrite what is already on the volume.
  cp -an /etc/gitlab/. "$CONFIG_DIR"/ 2>/dev/null || true
  rm -rf /etc/gitlab
  ln -s "$CONFIG_DIR" /etc/gitlab
  log "/etc/gitlab now lives on the volume (${CONFIG_DIR})"
fi

# Railway settings first; anything in GITLAB_OMNIBUS_CONFIG and /etc/gitlab/gitlab.rb
# is applied after them and wins.
export GITLAB_OMNIBUS_CONFIG="from_file('/assets/railway.rb')
${GITLAB_OMNIBUS_CONFIG:-}"

# Optional: create the one-time token the GitLab Runner service uses to register
# itself, once GitLab answers requests. Runs in the background.
if [ -n "${GITLAB_RUNNER_BOOTSTRAP_TOKEN:-}" ]; then
  /assets/railway-runner-bootstrap.sh &
fi

exec /assets/init-container "$@"
