ARG BASE_IMAGE=ubuntu:jammy
FROM node:24-bookworm-slim AS node-tools
RUN npm install --global ccstatusline@2.2.32

FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG PACKAGES="curl ca-certificates git unzip"
RUN if command -v apt-get >/dev/null; then \
      apt-get update && apt-get install -y --no-install-recommends $PACKAGES && \
      apt-get clean && rm -rf /var/lib/apt/lists/*; \
    elif command -v dnf >/dev/null; then \
      dnf install -y $PACKAGES && dnf clean all; \
    elif command -v apk >/dev/null; then \
      apk add --no-cache $PACKAGES; \
    fi

# Keep Node.js and ccstatusline outside the host /usr bind mount.
COPY --from=node-tools /usr/local/ /opt/node/
RUN mkdir -p /etc/claude-code && \
    printf '%s\n' '{"statusLine":{"type":"command","command":"/opt/node/bin/ccstatusline","padding":0}}' \
      > /etc/claude-code/managed-settings.json

ARG USER
ARG UID=1000
RUN test -n "$USER" || { echo "ERROR: USER build arg is required"; exit 1; } && \
    existing=$(getent passwd $UID | cut -d: -f1 || true) && \
    if [ -n "$existing" ] && [ "$existing" != "$USER" ]; then userdel "$existing"; fi && \
    useradd -m -s /bin/bash -u $UID $USER && \
    mkdir -p /home/$USER/.claude /home/$USER/.local/bin /home/$USER/.config && \
    chown $USER:$USER /home/$USER/.claude /home/$USER/.local /home/$USER/.local/bin /home/$USER/.config

COPY extra-build.sh /tmp/extra-build.sh
RUN bash /tmp/extra-build.sh && rm /tmp/extra-build.sh

USER $USER

ENV PATH=/home/$USER/.local/bin:/opt/node/bin:$PATH

ARG CLAUDE_VERSION=1
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install Codex into a baked, non-mounted dir (CODEX_HOME set inline, NOT via ENV):
# the runtime ~/.codex mount would otherwise shadow the binary that the installer
# places under $CODEX_HOME/packages/standalone. At runtime CODEX_HOME is unset, so it
# defaults to the mounted ~/.codex for config/auth while the binary stays baked here.
ARG CODEX_VERSION=1
RUN curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_HOME=$HOME/.local/share/codex CODEX_NON_INTERACTIVE=1 sh

ARG OPENCODE_VERSION=1
RUN curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path && \
    mv "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode" && \
    opencode --version

CMD ["claude"]
