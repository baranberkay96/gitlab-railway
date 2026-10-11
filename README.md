# Deploy and Host GitLab CE with Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/gitlab-ce-19-devops-platform?referralCode=20H68q)

GitLab Community Edition is an open-source DevOps platform: Git repositories, merge requests with code review, issues, boards, wikis and built-in CI/CD. This community template runs the official GitLab Omnibus image on Railway with a persistent volume, Git over SSH through a TCP proxy, and a CI runner that registers itself.

## About Hosting GitLab CE

GitLab Omnibus bundles nginx, Puma, Sidekiq, Gitaly, gitlab-shell, PostgreSQL and Redis in one container. Hosting it well means keeping three kinds of state: repositories and the database, the configuration with `gitlab-secrets.json` (the keys that decrypt CI variables and 2FA secrets), and the SSH host keys. Railway allows one volume per service, so this template keeps all of it on a single volume and builds GitLab's configuration from service variables: external URL, SSH host and port, memory profile and optional SMTP. A separate GitLab Runner service uses the shell executor, because Railway has no Docker-in-Docker, and registers itself with a short-lived token that is revoked after use.

## Common Use Cases

- Private Git hosting for a team or company that wants code on infrastructure it controls
- Code review with merge requests, protected branches and approval rules
- Issue tracking, boards, milestones and project wikis next to the code
- Lightweight CI pipelines (tests, linting, builds, scripted deploys) on the bundled shell runner
- A central GitLab for external runners on your own VMs or Kubernetes clusters

## Dependencies for GitLab CE Hosting

- GitLab CE 19.4.1 (official `gitlab/gitlab-ce` Omnibus image, with bundled PostgreSQL, Redis, Gitaly and nginx)
- GitLab Runner 19.4.1 (official `gitlab/gitlab-runner` Ubuntu image, shell executor)
- A Railway volume for GitLab data and one for the runner configuration
- A Railway TCP proxy for Git over SSH

### Deployment Dependencies

- GitLab Docker installation: https://docs.gitlab.com/install/docker/
- Omnibus configuration reference: https://docs.gitlab.com/omnibus/settings/
- Running GitLab in a memory-constrained environment: https://docs.gitlab.com/omnibus/settings/memory_constrained_envs/
- GitLab Runner shell executor: https://docs.gitlab.com/runner/executors/shell/
- GitLab upgrade paths: https://docs.gitlab.com/update/upgrade_paths/

### Implementation Details

| Service | Image | Role |
|---|---|---|
| GitLab | built from `services/gitlab` (`gitlab/gitlab-ce:19.4.1-ce.0` + entrypoint) | Web UI, API, Git over HTTPS and SSH, Sidekiq, Gitaly, bundled PostgreSQL and Redis; volume `/var/opt/gitlab` |
| GitLab Runner | built from `services/gitlab-runner` (`gitlab/gitlab-runner:ubuntu-v19.4.1` + tools) | Runs CI jobs with the shell executor; volume `/etc/gitlab-runner` |

**First login:** wait until the GitLab service is healthy (the first boot configures GitLab and creates the database, which takes several minutes). Open the public URL and sign in as `root` with the generated `GITLAB_ROOT_PASSWORD` from the GitLab service variables, then change it. New sign-ups require admin approval by default; turn sign-up off under Admin → Settings → General if the instance is private. Add your SSH key and clone with the SSH URL GitLab shows (it points to the TCP proxy host and port).

**CI/CD:** the runner appears under Admin → CI/CD → Runners a few minutes after GitLab is up and picks up untagged jobs. Jobs run directly in the runner container with git, curl, bash, jq, make, Python 3 and rsync available; the `image:` keyword is ignored because Railway cannot run Docker inside a container. Add more tools in `services/gitlab-runner/Dockerfile`, or register an external Docker runner against your GitLab URL for container-based jobs. Use this runner only for projects you trust, since jobs share its container.

**Scaling:** raise `GITLAB_PUMA_WORKERS` (about 700 MB each) or `GITLAB_SIDEKIQ_CONCURRENCY` and give the GitLab service more memory; the defaults fit 4–8 GB. GitLab itself runs as a single replica because it owns its volume. For more CI capacity raise `GITLAB_RUNNER_CONCURRENT` and the runner's resources.

**E-mail:** set `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASSWORD` and `GITLAB_EMAIL_FROM`. GitLab sends mail only over SMTP, and Railway allows outbound SMTP on the Pro plan.

**Versions:** GitLab is pinned in `services/gitlab/Dockerfile` (`GITLAB_VERSION`), the runner in `services/gitlab-runner/Dockerfile` (`RUNNER_VERSION`). Upgrade along GitLab's upgrade path, one required stop at a time, and keep the runner on the same minor version. Back up with `gitlab-backup create` (in the GitLab service shell) and keep a copy of `/etc/gitlab/gitlab-secrets.json` with it.

### Why Deploy GitLab CE on Railway?

Railway provides the persistent volume, HTTPS domain and TCP proxy GitLab needs, so a complete GitLab with SSH access and a working CI runner comes up from one template without managing a server. You pay for the resources GitLab actually uses and can give it more memory as your team grows.
