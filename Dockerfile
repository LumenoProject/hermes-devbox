# Hermes Devbox — customized Hermes Agent environment.
#
# Derived from the official image (nousresearch/hermes-agent, stable-desktop
# channel: the stable release gate's Bot Screen desktop variant, built with
# HERMES_BOT_DESKTOP=1 — Xvnc, XFCE components and apt Chromium included).
# Rules inherited from upstream docs (website/docs/user-guide/docker.md):
#   - NEVER override ENTRYPOINT/CMD: the s6-overlay supervision tree must own
#     PID 1; the dispatcher drops privileges to the `hermes` user (UID 10000).
#   - /opt/hermes is the immutable install tree; all mutable state lives in
#     /opt/data (HERMES_HOME), mounted from a volume at runtime.
#   - Do not clobber upstream-managed symlinks in /usr/local/bin
#     (python3, node, npm, npx, pnpm, ffmpeg, rg are PM-managed).
ARG HERMES_IMAGE=nousresearch/hermes-agent:stable-desktop
FROM ${HERMES_IMAGE}

SHELL ["/bin/bash", "-c"]
USER root

ARG DEBIAN_FRONTEND=noninteractive

ENV RUSTUP_HOME=/opt/rustup \
    RUSTUP_AUTO_INSTALL=0

# Bootstrap CA certificates, then switch the existing Debian sources to HTTPS.
# GitHub CLI from its official apt repository, plus devbox extras (Debian trixie).
# Base image already provides: gcc/g++/make/cmake, git, tmux, curl, procps,
# iputils-ping, xz-utils, openssh-client, docker-cli, Node.js 26, Python 3.14.
RUN set -euxo pipefail; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates; \
    sed -i 's|http://|https://|g' /etc/apt/sources.list.d/debian.sources; \
    apt-get update; \
    apt-get upgrade -y; \
    curl -fsSL --retry 3 https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg; \
    printf 'deb [arch=%s signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
        "$(dpkg --print-architecture)" > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        gh wget jq unzip openssl \
        locales libcap2-bin \
        nano vim sudo htop btop nvtop \
        build-essential pkg-config \
        net-tools iproute2 \
        iputils-tracepath iputils-arping \
        traceroute mtr-tiny inetutils-telnet \
        bind9-dnsutils netcat-openbsd tcpdump iperf3 \
        libgl1 libegl1 libxi6 libxrender1 libsm6 \
        libxxf86vm1 libxinerama1 libxcursor1; \
    if [[ -n "$(getcap /usr/bin/nvtop)" ]]; then \
        setcap -r /usr/bin/nvtop; \
    fi; \
    printf '%s\n' 'set -g mouse on' > /etc/tmux.conf; \
    printf '%s\n' 'set tabsize 4' >> /etc/nanorc; \
    printf '%s\n' 'en_US.UTF-8 UTF-8' > /etc/locale.gen; \
    locale-gen; \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8; \
    ln -s "$(command -v traceroute)" /usr/local/bin/tracert; \
    rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8

# Apply shared toolchain locations to future login users too.
RUN set -eux; \
    printf '%s\n' \
        'export RUSTUP_HOME=/opt/rustup' \
        'export RUSTUP_AUTO_INSTALL=0' \
        > /etc/profile.d/99-dev-tools.sh; \
    printf '%s\n' \
        'RUSTUP_HOME=/opt/rustup' \
        'RUSTUP_AUTO_INSTALL=0' \
        >> /etc/environment

# uv: latest stable, globally installed (upstream keeps its PM-pinned uv under
# /opt/hermes/tools; /usr/local/bin/uv does not shadow any base-image symlink).
# No CPython is preinstalled: the image already ships Python 3.14 as
# /usr/local/bin/python3, and uv-managed Pythons would clobber that symlink.
RUN set -euxo pipefail; \
    curl -fsSL --retry 3 https://astral.sh/uv/install.sh -o /tmp/uv-install.sh; \
    UV_UNMANAGED_INSTALL=/usr/local/bin sh /tmp/uv-install.sh; \
    rm -f /tmp/uv-install.sh; \
    uv --version

# Blender LTS: official Linux x64 tarball and SHA256 verification.
ARG BLENDER_VERSION=5.2.4
RUN set -euxo pipefail; \
    test "$(dpkg --print-architecture)" = amd64; \
    tmpdir="$(mktemp -d)"; \
    archive="blender-${BLENDER_VERSION}-linux-x64.tar.xz"; \
    base="https://download.blender.org/release/Blender${BLENDER_VERSION%.*}"; \
    curl -fsSL --retry 3 "${base}/${archive}" -o "${tmpdir}/${archive}"; \
    curl -fsSL --retry 3 "${base}/blender-${BLENDER_VERSION}.sha256" -o "${tmpdir}/SHA256"; \
    checksum="$(awk -v f="${archive}" '$2 == f || $2 == "*" f {print $1}' "${tmpdir}/SHA256")"; \
    test -n "${checksum}"; \
    printf '%s  %s\n' "${checksum}" "${tmpdir}/${archive}" | sha256sum -c -; \
    tar -xJf "${tmpdir}/${archive}" -C /opt; \
    mv "/opt/blender-${BLENDER_VERSION}-linux-x64" /opt/blender; \
    ln -s /opt/blender/blender /usr/local/bin/blender; \
    rm -rf "${tmpdir}"; \
    blender --version

# Go: latest stable release from Go's official JSON API.
RUN set -euxo pipefail; \
    arch="$(dpkg --print-architecture)"; \
    case "${arch}" in amd64|arm64) ;; *) exit 1 ;; esac; \
    info="$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | \
        jq -r --arg arch "${arch}" \
        '[.[] | select(.stable == true)][0].files[] | select(.os == "linux" and .arch == $arch and .kind == "archive") | [.filename, .sha256] | @tsv')"; \
    read -r filename checksum <<< "${info}"; \
    test -n "${filename}"; \
    test -n "${checksum}"; \
    tmpdir="$(mktemp -d)"; \
    curl -fsSL --retry 3 "https://go.dev/dl/${filename}" -o "${tmpdir}/${filename}"; \
    printf '%s  %s\n' "${checksum}" "${tmpdir}/${filename}" | sha256sum -c -; \
    tar -xzf "${tmpdir}/${filename}" -C /usr/local; \
    ln -s /usr/local/go/bin/go /usr/local/bin/go; \
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt; \
    rm -rf "${tmpdir}"; \
    go version

# Rust: latest stable toolchain; rustup/toolchain are globally readable.
# User-specific Cargo crate caches continue to use the user's account
# (for the runtime `hermes` user that is /opt/data/.cargo, persisted on the volume).
RUN set -euxo pipefail; \
    mkdir -p /opt/rustup /opt/rust-cargo; \
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 \
        https://sh.rustup.rs -o /tmp/rustup.sh; \
    CARGO_HOME=/opt/rust-cargo RUSTUP_HOME=/opt/rustup \
        sh /tmp/rustup.sh -y --no-modify-path \
        --profile default --default-toolchain stable; \
    for tool in rustup rustc cargo rustdoc rustfmt cargo-fmt cargo-clippy clippy-driver; do \
        if [[ -x "/opt/rust-cargo/bin/${tool}" ]]; then \
            ln -s "/opt/rust-cargo/bin/${tool}" "/usr/local/bin/${tool}"; \
        fi; \
    done; \
    chmod -R a+rX /opt/rustup /opt/rust-cargo; \
    rm -f /tmp/rustup.sh; \
    rustc --version; \
    cargo --version

# ENTRYPOINT (/opt/hermes/docker/entrypoint-dispatch.sh), CMD, VOLUME /opt/data,
# EXPOSE-less port conventions and the `hermes` runtime user are all inherited
# unchanged from the base image on purpose — see the header comment.
