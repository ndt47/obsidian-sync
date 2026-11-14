# Obsidian Headless (official Obsidian Sync client, no desktop app) plus a guarded loop.
# Pinned on purpose: bump OBSIDIAN_HEADLESS_VERSION deliberately after reading the changelog.
# better-sqlite3 (its state DB) ships linux-x64 glibc prebuilds for Node 22, so no toolchain is needed.
ARG NODE_TAG=22-bookworm-slim
FROM node:${NODE_TAG}

ARG OBSIDIAN_HEADLESS_VERSION=0.0.14
RUN npm install -g obsidian-headless@${OBSIDIAN_HEADLESS_VERSION} \
 && npm cache clean --force \
 && ob --version

COPY --chmod=0755 sync-loop.sh /usr/local/bin/sync-loop.sh

# Runs as the vault's owner (obsidian 3018:3011) via compose `user:`.
ENV HOME=/state XDG_CONFIG_HOME=/state/config VAULT_PATH=/vault
WORKDIR /vault
ENTRYPOINT ["/usr/local/bin/sync-loop.sh"]
