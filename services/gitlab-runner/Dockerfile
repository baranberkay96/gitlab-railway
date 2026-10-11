# GitLab Runner with the shell executor for Railway (no Docker-in-Docker).
#
# CI jobs run inside this container as the `gitlab-runner` user. Add the
# toolchains your pipelines need to the apt-get line below (or install them in
# `before_script`, as the job user has no root access).
ARG RUNNER_VERSION=ubuntu-v19.4.1
FROM gitlab/gitlab-runner:${RUNNER_VERSION}

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        jq \
        make \
        openssh-client \
        python3 \
        python3-venv \
        rsync \
        unzip \
        zip \
    && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 railway-runner.sh /usr/local/bin/railway-runner.sh

ENTRYPOINT ["/usr/local/bin/railway-runner.sh"]
CMD []
