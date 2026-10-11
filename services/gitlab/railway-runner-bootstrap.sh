#!/bin/bash
# Background helper started by railway-entrypoint.sh.
#
# Waits until GitLab serves requests, then makes sure a personal access token
# with the value of GITLAB_RUNNER_BOOTSTRAP_TOKEN exists for the root user, with
# only the `create_runner` scope and a 30-day expiry. The GitLab Runner service
# uses it once to create and register an instance runner, then revokes it.
#
# Runs once per token value (marker file on the volume), because booting the
# Rails console takes about a minute and several hundred MB of RAM.
set -u

MARKER=/var/opt/gitlab/.railway-runner-bootstrap
PORT="${PORT:-80}"

log() { echo "[railway-runner-bootstrap] $*"; }

token_hash=$(printf '%s' "${GITLAB_RUNNER_BOOTSTRAP_TOKEN}" | sha256sum | cut -d' ' -f1)
if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$token_hash" ]; then
  log "bootstrap token already handled; nothing to do"
  exit 0
fi

# Wait up to 60 minutes for GitLab (first boot runs reconfigure and migrations).
for _ in $(seq 1 360); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:${PORT}/users/sign_in" || true)
  [ "$code" = "200" ] && break
  sleep 10
done
if [ "${code:-}" != "200" ]; then
  log "GitLab did not become ready; skipping (runs again on next boot)"
  exit 0
fi

log "GitLab is up; ensuring the runner bootstrap token exists"
if gitlab-rails runner /assets/railway-runner-bootstrap.rb; then
  printf '%s' "$token_hash" > "$MARKER"
  chmod 0600 "$MARKER"
else
  log "failed (see output above); will retry on next boot"
fi
