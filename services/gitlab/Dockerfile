# GitLab Community Edition (official Omnibus image) for Railway.
#
# Adds only a small entrypoint: /etc/gitlab is moved onto the single Railway
# volume (/var/opt/gitlab), settings come from service variables
# (railway.rb, loaded via GITLAB_OMNIBUS_CONFIG), and an optional helper creates
# the one-time token the GitLab Runner service registers with.
#
# Upgrade: change GITLAB_VERSION (follow GitLab's upgrade path, one required stop
# at a time) and redeploy. The image's init checks the path and runs migrations.
ARG GITLAB_VERSION=19.4.1-ce.0
FROM gitlab/gitlab-ce:${GITLAB_VERSION}

COPY --chmod=0644 railway.rb /assets/railway.rb
COPY --chmod=0644 railway-runner-bootstrap.rb /assets/railway-runner-bootstrap.rb
COPY --chmod=0755 railway-entrypoint.sh /assets/railway-entrypoint.sh
COPY --chmod=0755 railway-runner-bootstrap.sh /assets/railway-runner-bootstrap.sh

# 80 = nginx (Railway public domain), 22 = sshd (Railway TCP proxy)
EXPOSE 80 22

CMD ["/assets/railway-entrypoint.sh"]
