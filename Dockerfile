# syntax=docker/dockerfile:1
#
# devcontainer-aws-base
#
# Sibling of devcontainer-node-base, for AWS work: certification study
# and small AWS projects. Carries three runtimes (Java, Python, Node)
# because AWS work spans all three, plus the AWS/IaC toolchain.
#
# Base is the Eclipse Temurin JDK on Ubuntu 24.04 (noble). There is no
# Debian variant of eclipse-temurin, so this is a distro switch from
# node-base's Debian 12. Distro tag is pinned deliberately: the floating
# `21-jdk` tag can move between Ubuntu releases without warning.
FROM eclipse-temurin:21-jdk-noble

##################################################
########### TEMPORARY ROOT USER STARTS ###########
##################################################

# Ubuntu 24.04 ships a stock `ubuntu` user at uid 1000. It has to go
# before our own uid-1000 user can be created, or useradd fails in a
# confusing way.
RUN userdel -r ubuntu 2>/dev/null || true
RUN groupadd -g 1000 dev && \
    useradd -u 1000 -g dev -m -s /bin/bash dev

RUN mkdir -p /app && chown dev:dev /app

# - tcc + libc6-dev: required for neovim LSP
# - ripgrep: required for some neovim telescope functions
# - libicu74: required by GCM. node-base pulls this in via `rpm` as a
#   proxy on Debian; on noble we can just name it.
# - xz-utils: the Temurin base has no xz, so the Node tarball
#   (.tar.xz) cannot be unpacked without it
# - jq: indispensable for working with AWS CLI output
# - less: the AWS CLI's default pager
# - python3/venv/pipx: see the PEP 668 note below
RUN apt-get update && apt-get install -y --no-install-recommends \
      sudo git curl unzip zip xz-utils ca-certificates gnupg less \
      tcc libc6-dev ripgrep tmux libicu74 jq \
      python3 python3-venv python3-pip pipx \
 && rm -rf /var/lib/apt/lists/*

# Passwordless sudo for the dev user. Not safe for a production image;
# fine (and necessary) for a devcontainer.
RUN echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/dev && \
    chmod 0440 /etc/sudoers.d/dev

# Node 24.20.0 from the official tarball rather than an apt repo, so the
# version is exactly pinned in the house style.
RUN curl -Lo /tmp/node.tar.xz \
      https://nodejs.org/dist/v24.20.0/node-v24.20.0-linux-x64.tar.xz && \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 \
      --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md && \
    rm /tmp/node.tar.xz

# `corepack enable` must run as root - it installs its shims into
# /usr/local/bin, which dev cannot write to. The matching
# `corepack prepare` runs as dev further down; see the note there.
RUN corepack enable

# AWS CLI v2 2.36.32
RUN curl -Lo /tmp/awscli.zip \
      https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.36.32.zip && \
    unzip -q /tmp/awscli.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscli.zip /tmp/aws

# Session Manager plugin. Lets you open a shell on an EC2 instance with
# no SSH, no key pair and no bastion. Only a "latest" artifact is
# published, so this one cannot be pinned.
RUN curl -Lo /tmp/ssm.deb \
      https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb && \
    dpkg -i /tmp/ssm.deb && \
    rm /tmp/ssm.deb

# AWS SAM CLI v1.165.0 (`sam local invoke` for Lambda work)
RUN curl -Lo /tmp/sam.zip \
      https://github.com/aws/aws-sam-cli/releases/download/v1.165.0/aws-sam-cli-linux-x86_64.zip && \
    unzip -q /tmp/sam.zip -d /tmp/sam && \
    /tmp/sam/install && \
    rm -rf /tmp/sam.zip /tmp/sam

# Terraform 1.15.9. Deliberately not 1.16.x, which is days old.
RUN curl -Lo /tmp/terraform.zip \
      https://releases.hashicorp.com/terraform/1.15.9/terraform_1.15.9_linux_amd64.zip && \
    unzip -q /tmp/terraform.zip -d /tmp && \
    install -D /tmp/terraform /usr/local/bin/terraform && \
    rm /tmp/terraform.zip /tmp/terraform

# kubectl v1.37.0
RUN curl -Lo /tmp/kubectl https://dl.k8s.io/release/v1.37.0/bin/linux/amd64/kubectl && \
    install -D -m 0755 /tmp/kubectl /usr/local/bin/kubectl && \
    rm /tmp/kubectl

# helm v4.2.4
RUN curl -Lo /tmp/helm.tar.gz https://get.helm.sh/helm-v4.2.4-linux-amd64.tar.gz && \
    tar -xf /tmp/helm.tar.gz -C /tmp linux-amd64/helm && \
    install -D /tmp/linux-amd64/helm /usr/local/bin/helm && \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

# eksctl v0.230.0. Retained for EKS lab exercises only - no project here
# requires Kubernetes.
RUN curl -Lo /tmp/eksctl.tar.gz \
      https://github.com/eksctl-io/eksctl/releases/download/v0.230.0/eksctl_Linux_amd64.tar.gz && \
    tar -xf /tmp/eksctl.tar.gz -C /tmp eksctl && \
    install -D /tmp/eksctl /usr/local/bin/eksctl && \
    rm /tmp/eksctl.tar.gz /tmp/eksctl

# AWS CDK 2.1139.0
RUN npm install -g aws-cdk@2.1139.0 && npm cache clean --force

# Pre-create every path that devcontainer.json mounts a named volume
# over. Docker creates missing mount points as root:root, which would
# leave dev unable to write to them.
RUN mkdir -p /home/dev/.aws \
             /home/dev/.kube \
             /home/dev/.gradle \
             /home/dev/.terraform.d/plugin-cache \
             /home/dev/.venvs \
 && chown -R dev:dev /home/dev

# Switch to dev for all development operations
USER dev
ENV USER=dev
##################################################
############ TEMPORARY ROOT USER ENDS ############
##################################################

ENV PATH="/home/dev/.local/bin:$PATH"
ENV TF_PLUGIN_CACHE_DIR="/home/dev/.terraform.d/plugin-cache"
# Stops the AWS CLI dropping every response into a pager.
ENV AWS_PAGER=""
# Forward-looking hook for a language-profile switch in neovim-config.
# The config does not read this yet - see README.
ENV JSLOG_LSP_PROFILE=aws

# pnpm 10.21.0, matching node-base. This must run as dev, not root:
# `corepack prepare` caches the pinned version under $HOME, so doing it
# as root leaves dev with an empty cache and corepack silently fetches
# the latest pnpm at runtime instead of the pinned one.
RUN corepack prepare pnpm@10.21.0 --activate

# Ubuntu 24.04 enforces PEP 668, so `pip install boto3` at the system
# level fails with externally-managed-environment. A shared venv covers
# ad-hoc boto3 scripting; pipx covers Python CLI tools; per-project
# venvs cover everything else.
RUN python3 -m venv /home/dev/.venvs/aws && \
    /home/dev/.venvs/aws/bin/pip install --no-cache-dir --upgrade pip boto3
RUN echo 'alias awspy="source /home/dev/.venvs/aws/bin/activate"' >> ~/.bashrc

# lazygit v0.63.1
RUN curl -Lo /tmp/lazygit.tar.gz \
      "https://github.com/jesseduffield/lazygit/releases/download/v0.63.1/lazygit_0.63.1_linux_x86_64.tar.gz" && \
    tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit && \
    sudo install -D /tmp/lazygit /usr/local/bin/lazygit && \
    rm /tmp/lazygit.tar.gz /tmp/lazygit

# Neovim v0.11.2 (AppImage extracted because AppImages cannot mount
# inside containers without FUSE).
RUN curl -Lo /tmp/nvim.appimage \
      https://github.com/neovim/neovim/releases/download/v0.11.2/nvim-linux-x86_64.appimage && \
    chmod u+x /tmp/nvim.appimage && \
    cd /tmp && /tmp/nvim.appimage --appimage-extract && \
    rm /tmp/nvim.appimage && \
    sudo mv /tmp/squashfs-root /usr/bin/nvim-appimage-extract && \
    sudo ln -s /usr/bin/nvim-appimage-extract/AppRun /usr/bin/nvim
# Runs as dev, so the checkout is dev-owned and editable in place. This is
# the only source of the config - no volume is mounted over it, so a rebuild
# always lands the current neovim-config and always discards local edits.
# Anything worth keeping gets committed and pushed to that repo.
RUN git clone https://github.com/js-jslog/neovim-config.git /home/dev/.config/nvim

# Embedded tmux configuration, symlinked into /etc/tmux.conf so it
# applies system-wide for any user inside the container. Required for
# the embedded Neovim workflow's keybindings.
RUN git clone https://github.com/js-jslog/tmux-config.git /home/dev/.config/tmux-config && \
    sudo ln -s /home/dev/.config/tmux-config/.tmux.xterm.conf /etc/tmux.conf

# GCM
RUN curl -Lo /tmp/gcm-linux_amd64.2.4.1.deb https://github.com/git-ecosystem/git-credential-manager/releases/download/v2.4.1/gcm-linux_amd64.2.4.1.deb && \
    sudo dpkg -i /tmp/gcm-linux_amd64.2.4.1.deb && \
    rm /tmp/gcm-linux_amd64.2.4.1.deb
RUN /usr/local/bin/git-credential-manager configure
RUN git config --global credential.credentialStore plaintext

# Claude
RUN echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
RUN curl -fsSL https://claude.ai/install.sh | bash

# git config
RUN git config --global user.name "js-jslog"
RUN git config --global user.email "josephsinfield@yahoo.com"
RUN git config --global merge.tool "nvimdiff"
RUN git config --global core.editor "nvim"

# The project copy comes last, unlike node-base, so that editing this
# repo does not invalidate the cached tool layers above. Rebuilds while
# iterating are then seconds rather than minutes.
WORKDIR /app
COPY --chown=dev:dev . .

# Allow git repo symlinks to be manifest as such
RUN git config core.symlinks true
# Reset .devcontainer.json from Windows prep change, and allow broken
# .claude symlinks to be returned to functionality.
RUN git reset --hard

# Scratch space for arbitrary clones - lab exercises, other projects.
# Gitignored, and persisted by the workspace volume.
RUN mkdir -p /app/work

# Keep container running for devcontainer life. Required when using
# `overrideCommand: false` in the devcontainer.json which is essential
# for the DinD feature's entrypoint to start dockerd
CMD ["sleep", "infinity"]
