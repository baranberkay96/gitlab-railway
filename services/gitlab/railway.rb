# GitLab Omnibus settings for Railway.
#
# Loaded through GITLAB_OMNIBUS_CONFIG (set by railway-entrypoint.sh), which the
# image evaluates *before* /etc/gitlab/gitlab.rb. Anything you put in gitlab.rb
# (it lives on the volume) or append to GITLAB_OMNIBUS_CONFIG therefore wins.
# Every value below comes from a service variable so the template can be tuned
# without editing files.

def railway_env(name, default = nil)
  value = ENV[name].to_s.strip
  value.empty? ? default : value
end

def railway_flag(name, default)
  %w[1 true yes on].include?(railway_env(name, default.to_s).downcase)
end

# --- URL and reverse proxy --------------------------------------------------
# Railway terminates TLS at its edge and forwards plain HTTP to $PORT.
gitlab_host = railway_env('GITLAB_HOST') || railway_env('RAILWAY_PUBLIC_DOMAIN') || 'localhost'
gitlab_scheme = railway_env('GITLAB_EXTERNAL_SCHEME', 'https')
external_url "#{gitlab_scheme}://#{gitlab_host}"
letsencrypt['enable'] = false

gitlab_rails['nginx']['listen_port'] = railway_env('PORT', '80').to_i
gitlab_rails['nginx']['listen_https'] = false
# IPv4 and IPv6: Railway's private network and healthcheck use both.
gitlab_rails['nginx']['listen_addresses'] = ['0.0.0.0', '[::]']
gitlab_rails['nginx']['client_max_body_size'] = railway_env('GITLAB_MAX_BODY_SIZE', '0')
if gitlab_scheme == 'https'
  gitlab_rails['nginx']['proxy_set_headers'] = {
    'X-Forwarded-Proto' => 'https',
    'X-Forwarded-Ssl' => 'on'
  }
end
nginx['worker_processes'] = railway_env('GITLAB_NGINX_WORKERS', '2').to_i

# Real client IPs from Railway's edge proxy (private and carrier-grade NAT ranges).
trusted = railway_env('GITLAB_TRUSTED_PROXIES', '10.0.0.0/8,100.64.0.0/10,172.16.0.0/12,192.168.0.0/16,fd00::/8')
                .split(',').map(&:strip).reject(&:empty?)
gitlab_rails['trusted_proxies'] = trusted
gitlab_rails['nginx']['real_ip_trusted_addresses'] = trusted
gitlab_rails['nginx']['real_ip_header'] = 'X-Forwarded-For'
gitlab_rails['nginx']['real_ip_recursive'] = 'on'

# --- Git over SSH through Railway's TCP proxy ---------------------------------
# sshd listens on 22 inside the container; the TCP proxy publishes it on a
# random public host:port, which is what GitLab shows in clone URLs.
ssh_host = railway_env('GITLAB_SSH_HOST') || railway_env('RAILWAY_TCP_PROXY_DOMAIN')
ssh_port = railway_env('GITLAB_SSH_PORT') || railway_env('RAILWAY_TCP_PROXY_PORT')
gitlab_rails['gitlab_ssh_host'] = ssh_host if ssh_host
gitlab_rails['gitlab_shell_ssh_port'] = ssh_port.to_i if ssh_port

# --- First-boot admin -------------------------------------------------------
# Used only when the database is seeded (first boot). Change it in GitLab later.
root_password = railway_env('GITLAB_ROOT_PASSWORD')
gitlab_rails['initial_root_password'] = root_password if root_password
gitlab_rails['store_initial_root_password'] = false
gitlab_rails['display_initial_root_password'] = false

# --- Memory profile (fits a 4-8 GB service) -----------------------------------
puma['worker_processes'] = railway_env('GITLAB_PUMA_WORKERS', '2').to_i
puma['min_threads'] = railway_env('GITLAB_PUMA_THREADS', '4').to_i
puma['max_threads'] = railway_env('GITLAB_PUMA_THREADS', '4').to_i
sidekiq['concurrency'] = railway_env('GITLAB_SIDEKIQ_CONCURRENCY', '10').to_i

# Release freed memory back to the OS sooner (GitLab memory-constrained guide).
malloc_conf = 'dirty_decay_ms:1000,muzzy_decay_ms:1000'
gitlab_rails['env'] = { 'MALLOC_CONF' => malloc_conf }
gitaly['env'] = { 'MALLOC_CONF' => malloc_conf, 'GITALY_COMMAND_SPAWN_MAX_PARALLEL' => '2' }
gitaly['configuration'] = {
  concurrency: [
    { 'rpc' => '/gitaly.SmartHTTPService/PostReceivePack', 'max_per_repo' => 3 },
    { 'rpc' => '/gitaly.SSHService/SSHUploadPack', 'max_per_repo' => 3 }
  ]
}

# Bundled Prometheus, Alertmanager and exporters cost ~300 MB; off unless asked for.
prometheus_monitoring['enable'] = railway_flag('GITLAB_PROMETHEUS_ENABLED', false)

# Bundled PostgreSQL: fixed buffers instead of a share of the host's RAM, and
# dynamic shared memory in the data directory instead of the container's small /dev/shm.
postgresql['shared_buffers'] = railway_env('GITLAB_POSTGRES_SHARED_BUFFERS', '256MB')
postgresql['dynamic_shared_memory_type'] = 'mmap'

# --- Components that need extra domains/ports or a Kubernetes cluster ---------
registry['enable'] = false
gitlab_pages['enable'] = false
gitlab_kas['enable'] = railway_flag('GITLAB_KAS_ENABLED', false)

# --- E-mail (optional; outbound SMTP needs Railway Pro) -----------------------
if (smtp_address = railway_env('SMTP_ADDRESS'))
  smtp_port = railway_env('SMTP_PORT', '587').to_i
  gitlab_rails['smtp_enable'] = true
  gitlab_rails['smtp_address'] = smtp_address
  gitlab_rails['smtp_port'] = smtp_port
  gitlab_rails['smtp_user_name'] = railway_env('SMTP_USER')
  gitlab_rails['smtp_password'] = railway_env('SMTP_PASSWORD')
  gitlab_rails['smtp_domain'] = railway_env('SMTP_DOMAIN', gitlab_host)
  gitlab_rails['smtp_authentication'] = railway_env('SMTP_AUTHENTICATION', 'login')
  if smtp_port == 465
    gitlab_rails['smtp_tls'] = true
  else
    gitlab_rails['smtp_enable_starttls_auto'] = true
  end
end
gitlab_rails['gitlab_email_from'] = railway_env('GITLAB_EMAIL_FROM') if railway_env('GITLAB_EMAIL_FROM')
gitlab_rails['gitlab_email_reply_to'] = railway_env('GITLAB_EMAIL_REPLY_TO') if railway_env('GITLAB_EMAIL_REPLY_TO')

# --- Backups ------------------------------------------------------------------
# `gitlab-backup create` writes to /var/opt/gitlab/backups (on the volume).
gitlab_rails['backup_keep_time'] = railway_env('GITLAB_BACKUP_KEEP_SECONDS', '604800').to_i
