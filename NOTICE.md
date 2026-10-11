# NOTICE — GitLab CE 19 DevOps Platform

## Software deployed (not redistributed)

| Component | Source | License |
|---|---|---|
| GitLab Community Edition (Omnibus package) | `gitlab/gitlab-ce:19.4.1-ce.0` — https://gitlab.com/gitlab-org/gitlab-foss, https://gitlab.com/gitlab-org/omnibus-gitlab | MIT (GitLab CE); Omnibus packaging Apache-2.0; bundled components under their own licenses |
| GitLab Runner | `gitlab/gitlab-runner:ubuntu-v19.4.1` — https://gitlab.com/gitlab-org/gitlab-runner | MIT |
| Ubuntu packages added to the runner image (jq, make, python3, rsync, zip, unzip, openssh-client) | Ubuntu 24.04 archive | Their respective licenses |

This template is a community template. It is not affiliated with or endorsed by GitLab Inc.

## Upstream files checked (2026-10-11)

- `gitlab-org/omnibus-gitlab` tag `19.4.1+ce.0`: `docker/Dockerfile`, `docker/assets/init-container` (pre/post reconfigure hooks, SSH host key generation in `/etc/gitlab`, `GITLAB_OMNIBUS_CONFIG` handling), `docker/assets/gitlab.rb`, `docker/assets/setup` (sshd service, `git` user home), `docker/assets/sshd_config` (from the image).
- `/opt/gitlab/etc/gitlab.rb.template` from the `19.4.1-ce.0` image (NGINX keys moved to `gitlab_rails['nginx']` in 19.2, `sidekiq['concurrency']`, `postgresql['dynamic_shared_memory_type']`, `prometheus_monitoring['enable']`).
- GitLab docs: Docker installation, memory-constrained environments, reverse proxy SSL termination, "create a personal access token programmatically", runner registration (`POST /user/runners`, `glrt-` authentication tokens), `DELETE /personal_access_tokens/self`.
- `gitlab-org/gitlab-runner` `v19.4.1`: image entrypoint and `gitlab-runner register --help` (environment variables read by `register`, to avoid name collisions).

## Adapted material

None copied. All files under `services/` were written for this template.

- **vergissberlin/railwayapp-gitlab** (`_upstream/vergissberlin__railwayapp-gitlab`, MIT License, Copyright (c) 2026 André Lademann) — read for comparison (an entrypoint that derives the Omnibus configuration from Railway variables). Credited for the idea; no file or text was copied.

## Not used

- Market templates `gitlab`, `gitlab-ce-railway`, `gitlab-ce`: service layout and settings compared only. The ideas of moving `/etc/gitlab` onto the volume and publishing SSH through a TCP proxy appear in `gitlab-ce-railway` (no license) and were implemented independently. All prose here is original.
