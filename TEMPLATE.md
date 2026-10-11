# GitLab CE 19 DevOps Platform — Railway template spec

## Listing

| Field | Value |
|---|---|
| Name | **GitLab CE 19 DevOps Platform** (version label `19` = GitLab major; GitLab writes versions without a "v") |
| Description | Self-hosted Git, merge requests, issues and wiki. Own your code. (64 chars) |
| Category | Other |
| Tags | gitlab, git, devops, ci-cd, code-review, issue-tracker, self-hosted |
| Icon | https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/gitlab.svg |
| User input at deploy | **None.** Root password and the runner bootstrap token are generated. |

The listing description from LISTINGS_ROUND2.md is kept unchanged: everything it promises is delivered. CI/CD is an addition (shell-executor runner, see below), not a promise of Docker-based CI.

## Base market template

- **`gitlab` "GitLab | Open Source GitHub Alternative on Railway"** (27 active / 55 total projects) — the base. Kept: official `gitlab/gitlab-ce` Omnibus image in one service, one volume at `/var/opt/gitlab`, TLS at Railway's edge with nginx on plain HTTP, memory-constrained settings (MALLOC_CONF, monitoring off), `PORT=80`. Fixed: floating `latest` tag; empty root password (anyone reaching the URL first could set it); `/etc/gitlab` not persisted, so `gitlab-secrets.json` and SSH host keys were regenerated on every redeploy (CI variables, 2FA secrets and runner tokens become unreadable; SSH host key changes); no SSH (no TCP proxy); no CI runner; `puma['worker_processes'] = 0` (single process, too small for the 4–8 GB target); NGINX keys deprecated since GitLab 19.2.
- `gitlab-ce-railway` (image based, 1 active) — read for comparison. It moves `/etc/gitlab` onto the volume in its start command and maps SSH through a TCP proxy; the same two ideas are used here, implemented independently in `services/gitlab/railway-entrypoint.sh` and `railway.rb`. Nothing copied (no license).
- `gitlab-ce` (repo `vergissberlin/railwayapp-gitlab`, MIT) — read for comparison (entrypoint that builds the Omnibus config from Railway variables). No file copied; credited in NOTICE.md.

## Pinned versions

| Service | Image | Tag | Release date | Checked |
|---|---|---|---|---|
| GitLab (built from `services/gitlab`) | `gitlab/gitlab-ce` | `19.4.1-ce.0` | 2026-09-23 | 2026-10-11 |
| GitLab Runner (built from `services/gitlab-runner`) | `gitlab/gitlab-runner` | `ubuntu-v19.4.1` | 2026-09 | 2026-10-11 |

`19.4.1-ce.0` is the current stable release (Docker Hub `latest` points to it; 19.5 is due on the third Thursday of October). Runner minor matches the GitLab minor, as GitLab recommends.

**Upgrades:** change `ARG GITLAB_VERSION` in `services/gitlab/Dockerfile` (or set a service variable `GITLAB_VERSION`, which Railway passes as a build argument) and redeploy. Follow GitLab's upgrade path (required stops; https://docs.gitlab.com/update/upgrade_paths/) one stop at a time — the image's init runs `gitlab-ctl upgrade-check` and refuses invalid jumps, then reconfigure runs the migrations. Bump the runner's `RUNNER_VERSION` to the same minor. Bundled PostgreSQL major upgrades are not automatic in the Docker image (`gitlab-ctl pg-upgrade`, see GitLab docs); take a backup first.

## Architecture

```
Internet ──HTTPS──▶ GitLab (Omnibus, one container, volume /var/opt/gitlab)
             │        ├─ nginx :80 ─▶ Workhorse ─▶ Puma (2 workers × 4 threads)
             │        ├─ Sidekiq (10 threads)    ├─ Gitaly    ├─ gitlab-shell
             │        ├─ PostgreSQL (bundled)    └─ Redis (bundled)
Internet ──TCP proxy──▶ sshd :22 (git over SSH)
                           ▲
GitLab Runner ──private network (http://gitlab.railway.internal)──┘
  (shell executor, volume /etc/gitlab-runner = config.toml)
```

**One volume.** Railway gives a service exactly one volume. GitLab normally uses three (`/etc/gitlab`, `/var/opt/gitlab`, `/var/log/gitlab`). The volume is mounted at `/var/opt/gitlab` (repositories, PostgreSQL, Redis, uploads, artifacts, backups). On start, `railway-entrypoint.sh` moves `/etc/gitlab` to `/var/opt/gitlab/railway-etc-gitlab` and symlinks it back, so `gitlab-secrets.json`, the SSH host keys and any hand edits to `gitlab.rb` persist. Logs (`/var/log/gitlab`) are ephemeral; they are streamed to Railway's log view by the image (`gitlab-ctl tail`).

**Configuration from variables.** `services/gitlab/railway.rb` is loaded through `GITLAB_OMNIBUS_CONFIG` before `/etc/gitlab/gitlab.rb`; it reads the service variables (host, SSH host/port, memory profile, SMTP). Anything in `gitlab.rb` or in the `GITLAB_OMNIBUS_CONFIG` variable is applied after it and wins.

**SSH.** sshd listens on port 22 in the container; the template's TCP proxy publishes it. `railway.rb` sets `gitlab_ssh_host`/`gitlab_shell_ssh_port` from `RAILWAY_TCP_PROXY_DOMAIN`/`RAILWAY_TCP_PROXY_PORT`, so clone URLs show `ssh://git@{proxy-host}:{proxy-port}/group/project.git`.

**CI runner without Docker-in-Docker.** Railway has no Docker daemon or privileged containers, so the Docker executor cannot work. The GitLab Runner service uses the **shell executor**: jobs run inside the runner container as user `gitlab-runner` with the tools in its Dockerfile (git, git-lfs, curl, bash, jq, make, python3, rsync, zip/unzip, openssh-client). The `image:` and `services:` keywords in `.gitlab-ci.yml` are ignored. Registration is automatic:
1. GitLab's entrypoint starts `railway-runner-bootstrap.sh` in the background. Once GitLab answers, it uses `gitlab-rails runner` (GitLab's documented "create a personal access token programmatically" method) to create a token for `root` whose value is `GITLAB_RUNNER_BOOTSTRAP_TOKEN`, scoped to `create_runner` only, expiring in 30 days. It runs once per token value (marker file on the volume).
2. The runner waits for GitLab, calls `POST /api/v4/user/runners` (instance runner, tags `railway,shell`, runs untagged jobs), registers with the returned `glrt-` token (`--clone-url` = private URL), revokes the bootstrap token (`DELETE /personal_access_tokens/self`) and starts. `config.toml` stays on its volume; later boots reuse it. Tokens are removed from the environment before jobs run.
3. Manual alternative: set `GITLAB_RUNNER_TOKEN` to a `glrt-` token from Admin → CI/CD → Runners → New instance runner (takes precedence). For Docker-based jobs, register an external runner on a VM against the public URL.

### Deviations from upstream (and why)

- `/etc/gitlab` lives inside the data volume (one volume per service).
- nginx listens on `0.0.0.0` and `[::]` (Railway private network and healthcheck use both); TLS terminated by Railway; `X-Forwarded-Proto: https` set as in GitLab's "reverse proxy SSL termination" docs (keys under `gitlab_rails['nginx']`, new in 19.2).
- Memory profile for a 4–8 GB service: Puma 2×4, Sidekiq 10, Prometheus stack off, MALLOC_CONF decay and Gitaly spawn/concurrency limits from GitLab's memory-constrained guide, PostgreSQL `shared_buffers=256MB` and `dynamic_shared_memory_type=mmap` (container `/dev/shm` is small).
- Container registry, Pages and KAS off (registry and Pages need their own domain/port; KAS can be enabled with a variable).

## Services

### GitLab

- **Source:** GitHub repo `baranberkay96/gitlab-railway`, root directory `/services/gitlab` (Dockerfile build)
- **Start command:** image default (`/assets/railway-entrypoint.sh` → `/assets/init-container`)
- **Healthcheck:** `/users/sign_in` (timeout 1800 s; first boot runs reconfigure and database migrations)
- **Public domain:** yes → target port `80`
- **TCP proxy:** port `22` (git over SSH)
- **Volume:** `/var/opt/gitlab`
- **Restart policy:** ON_FAILURE (max 10 retries)
- **Replicas:** 1 (owns the volume)

| Variable | Value | Description |
|---|---|---|
| `PORT` | `80` | Port GitLab's bundled nginx listens on; Railway routes the public domain and its healthcheck here. |
| `GITLAB_HOST` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Host name in GitLab's external URL (https://...). Change it to your custom domain after adding one, then redeploy. |
| `GITLAB_ROOT_PASSWORD` | `${{secret(24)}}` | Password of the 'root' administrator, applied once when the database is created. Change it in GitLab afterwards. |
| `GITLAB_RUNNER_BOOTSTRAP_TOKEN` | `${{secret(40)}}` | One-time token (create_runner scope only, 30-day expiry) that GitLab creates for root so the GitLab Runner service can register itself. The runner revokes it after use. Clear it to disable automatic runner registration. |
| `GITLAB_PUMA_WORKERS` | `2` | Puma web worker processes (~600-900 MB each). 0 = single process for very small instances. |
| `GITLAB_PUMA_THREADS` | `4` | Threads per Puma worker. |
| `GITLAB_SIDEKIQ_CONCURRENCY` | `10` | Sidekiq background job threads (GitLab default 20). |
| `GITLAB_POSTGRES_SHARED_BUFFERS` | `256MB` | shared_buffers of the bundled PostgreSQL. Raise it with the service's memory. |
| `GITLAB_PROMETHEUS_ENABLED` | `false` | Run the bundled Prometheus, Alertmanager and exporters (about 300 MB extra). |
| `GITLAB_KAS_ENABLED` | `false` | Run the GitLab agent server for Kubernetes (KAS), served under /-/kubernetes-agent/ on the same domain. |
| `SMTP_ADDRESS` | *(empty)* | Optional SMTP server for e-mail (notifications, password resets). Leave empty to disable e-mail. Outbound SMTP needs Railway Pro. |
| `SMTP_PORT` | `587` | SMTP port (587 STARTTLS, 465 implicit TLS). |
| `SMTP_USER` | *(empty)* | SMTP user name. |
| `SMTP_PASSWORD` | *(empty)* | SMTP password. |
| `GITLAB_EMAIL_FROM` | *(empty)* | Sender address for GitLab e-mails, e.g. gitlab@{your-domain}. |
| `GITLAB_OMNIBUS_CONFIG` | *(empty)* | Optional extra gitlab.rb Ruby lines, applied after the template's settings (e.g. registry or OmniAuth configuration). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `120` | Time for 'gitlab-ctl stop' to shut down PostgreSQL and the other components cleanly on redeploy. |

Also read by `railway.rb` when set (not created by the template): `GITLAB_SSH_HOST`, `GITLAB_SSH_PORT` (override the TCP proxy values, e.g. for a custom SSH host name), `GITLAB_TRUSTED_PROXIES`, `GITLAB_MAX_BODY_SIZE`, `GITLAB_NGINX_WORKERS`, `SMTP_DOMAIN`, `SMTP_AUTHENTICATION`, `GITLAB_EMAIL_REPLY_TO`, `GITLAB_BACKUP_KEEP_SECONDS`.

### GitLab Runner

- **Source:** GitHub repo `baranberkay96/gitlab-railway`, root directory `/services/gitlab-runner` (Dockerfile build)
- **Start command:** image default (`/usr/local/bin/railway-runner.sh`)
- **Healthcheck:** none (no HTTP endpoint; it polls GitLab)
- **Public domain:** no
- **TCP proxy:** none
- **Volume:** `/etc/gitlab-runner` (config.toml with the runner token)
- **Restart policy:** ALWAYS (waits for GitLab on first boot)
- **Replicas:** 1 (owns the volume; scale with `GITLAB_RUNNER_CONCURRENT` and memory)

| Variable | Value | Description |
|---|---|---|
| `GITLAB_INTERNAL_URL` | `http://${{GitLab.RAILWAY_PRIVATE_DOMAIN}}` | GitLab URL on the private network; used for the API, job traffic and git clones. |
| `GITLAB_RUNNER_BOOTSTRAP_TOKEN` | `${{GitLab.GITLAB_RUNNER_BOOTSTRAP_TOKEN}}` | Token used once to create and register an instance runner automatically, then revoked. |
| `GITLAB_RUNNER_TOKEN` | *(empty)* | Optional runner authentication token (glrt-...) from Admin > CI/CD > Runners > New instance runner. Takes precedence over the bootstrap token. |
| `GITLAB_RUNNER_CONCURRENT` | `2` | Jobs this runner executes at the same time. |
| `GITLAB_RUNNER_TAGS` | `railway,shell` | Tags of the automatically created runner (comma separated). |
| `GITLAB_RUNNER_RUN_UNTAGGED` | `true` | Let the automatically created runner pick up jobs without tags. |
| `GITLAB_RUNNER_DESCRIPTION` | `Railway shell runner` | Description of the automatically created runner in GitLab. |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | Grace period on redeploy. |

Variable names avoid the `RUNNER_*` / `CI_SERVER_*` prefixes that `gitlab-runner register` reads from the environment.

## Improvements over market templates

| # | Change | Why |
|---|---|---|
| 1 | Pinned `gitlab/gitlab-ce:19.4.1-ce.0` (leader: `latest`) | Reproducible deploys; upgrades follow GitLab's required stops. |
| 2 | `/etc/gitlab` persisted inside the single volume | `gitlab-secrets.json` and SSH host keys survive redeploys; without it CI variables, 2FA and runner tokens break after a redeploy (leader only pinned three of the keys). |
| 3 | Generated root password applied at first boot (leader: empty) | Nobody can claim the instance by visiting it first. |
| 4 | Git over SSH through a TCP proxy, clone URLs set from Railway variables | SSH push/pull works out of the box. |
| 5 | GitLab Runner service (shell executor) registered automatically with a scoped, self-revoking token | Pipelines run right after deploy, despite no Docker-in-Docker on Railway. |
| 6 | Memory profile for 4–8 GB: Puma 2×4, Sidekiq 10, monitoring off, MALLOC_CONF, Gitaly limits; all tunable via variables | Leader ran Puma in single mode; more throughput at a predictable footprint. |
| 7 | GitLab 19.2+ `gitlab_rails['nginx']` keys, dual-stack listen, trusted proxy ranges, `X-Forwarded-Proto` | Current configuration format; correct client IPs and HTTPS links behind Railway's edge. |
| 8 | Bundled PostgreSQL with fixed `shared_buffers` and `dynamic_shared_memory_type=mmap` | Avoids sizing from the host's RAM and `/dev/shm` limits in containers. |
| 9 | Optional SMTP from variables; extra `GITLAB_OMNIBUS_CONFIG` still honoured | E-mail without editing files; full Omnibus flexibility. |
| 10 | Tested locally (arm64, Railway-like: no VOLUME mounts, `--init`, single volume): first boot, root login password, SSH clone through a mapped port, automatic runner registration, a CI pipeline on the shell runner, token revocation, redeploy with the same secrets and no new SSH host keys | Fewer surprises on the first Railway deploy. |

## First login

1. Wait for the first deploy to turn healthy (reconfigure + migrations: about 3 minutes locally with 4 vCPUs, longer on a cold Railway host; healthcheck timeout 30 minutes).
2. Open the public URL and sign in as `root` with `GITLAB_ROOT_PASSWORD` (GitLab service → Variables). Change the password.
3. Admin → Settings → General → Sign-up restrictions: new sign-ups need admin approval by default; turn sign-up off if the instance is private.
4. Add your SSH key (Preferences → SSH Keys) and push. Clone URLs already use the TCP proxy host and port.
5. Admin → CI/CD → Runners: "Railway shell runner" appears online a few minutes after GitLab is healthy.

## Scaling

- **Web/API:** raise `GITLAB_PUMA_WORKERS` (≈ +700 MB each) and the service's memory. **Background jobs:** raise `GITLAB_SIDEKIQ_CONCURRENCY`.
- **GitLab service:** cannot run multiple replicas (Omnibus with its own PostgreSQL on the volume). For large installations GitLab recommends external PostgreSQL/Redis/object storage; that is out of scope for this template.
- **CI capacity:** raise `GITLAB_RUNNER_CONCURRENT` and the runner's memory/CPU, or duplicate the runner service (each copy has its own volume and registers its own runner via a `glrt-` token in `GITLAB_RUNNER_TOKEN`).

## Backups

- Railway volume backups cover the GitLab volume (database, repositories, uploads, config incl. `gitlab-secrets.json`).
- Application backup: open a shell on the GitLab service and run `gitlab-backup create` (written to `/var/opt/gitlab/backups`, pruned after `GITLAB_BACKUP_KEEP_SECONDS`, 7 days). Copy it off the volume together with `/etc/gitlab/gitlab-secrets.json` (not part of `gitlab-backup`).

## Resource estimate

Railway prices: RAM $10/GB-month, vCPU $20/vCPU-month, volume $0.15/GB-month. Idle figures measured locally (arm64, 4 vCPU limit) a few minutes after first boot: GitLab 3.9 GB, runner 23 MB; fresh data on the volume 463 MB.

| Service | Idle RAM | Typical RAM (5–25 developers) | Typical CPU |
|---|---|---|---|
| GitLab (Puma 2×4, Sidekiq 10, Gitaly, PostgreSQL, Redis, nginx) | 3.9 GB | 4.5–5.5 GB | 0.5 vCPU (bursts during pushes, merges, migrations) |
| GitLab Runner (shell, 2 concurrent jobs) | 25 MB | 0.5 GB average (jobs) | 0.25 vCPU average |
| **Total** | **≈3.9 GB** (≈0.1 vCPU) | **≈5.5 GB** | **≈0.75 vCPU** |

- **Idle:** ≈ $39 RAM + $2 CPU + $0.2 volumes ≈ **$41/month**.
- **Typical:** ≈ $55 RAM + $15 CPU + $1.5 volumes (10 GB) ≈ **$72/month**.
- **Minimum plan:** Hobby (GitLab needs ~4 GB; Trial's 1 GB per service is not enough). Hobby's 5 GB volume limit fits a small team; Pro is recommended for larger repositories, backups on the volume, and outbound SMTP.

## Verification checklist

- [ ] Both Dockerfile builds succeed on Railway (GitLab base image ~1.5 GB compressed).
- [ ] GitLab logs: `[railway] /etc/gitlab now lives on the volume`, then reconfigure, then `[railway-runner-bootstrap] created token …`; deployment healthy on `/users/sign_in`.
- [ ] Sign in as `root` with `GITLAB_ROOT_PASSWORD`; links in the UI use `https://{public-domain}`.
- [ ] Runner logs: `created instance runner #…`, `registered runner`, `bootstrap token revoke: HTTP 204`; Admin → Runners shows it online.
- [ ] Create a project with a `.gitlab-ci.yml` (`script: [echo hello]`) → pipeline passes on the shell runner.
- [ ] Add an SSH key, `git clone ssh://git@{tcp-proxy-host}:{tcp-proxy-port}/root/{project}.git` works; push works.
- [ ] Redeploy GitLab: no "Generating ssh_host_…" lines, root login still works, CI variables set before the redeploy are still readable.
- [ ] Redeploy the runner: `using the runner already registered`.

## Open questions

- **Healthcheck timeout 1800 s:** above the 1200 s used in round-1 tests; a market GitLab template uses 7200 s, so the value should be accepted. First-boot time on Railway hardware not measured.
- **Railway edge source addresses:** trusted proxy ranges are private/CGNAT ranges; if Railway's edge uses other addresses, GitLab logs the edge IP instead of the client IP (functionality unaffected).
- **`/dev/shm` and SysV shared memory on Railway** not inspected; `dynamic_shared_memory_type=mmap` avoids depending on them.
- **Container registry / Pages** need extra public domains on other ports; not configured (can be added with `GITLAB_OMNIBUS_CONFIG` and a second domain).
- **Shell executor isolation:** jobs share the runner container; untrusted projects should not use this runner (use protected/tagged runners or an external Docker runner).
