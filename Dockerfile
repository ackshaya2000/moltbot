# -------------------------
# 1) Builder stage
# -------------------------
FROM node:22-bookworm AS builder

# Enable pnpm (corepack)
RUN corepack enable

WORKDIR /app

# (Optional) Extra apt packages hook
ARG CLAWDBOT_DOCKER_APT_PACKAGES=""
RUN if [ -n "$CLAWDBOT_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $CLAWDBOT_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# IMPORTANT: Railway 1GB plans often SIGKILL TypeScript builds.
# This caps TS/Node memory during build to reduce OOM kills.
# You can tweak 768 -> 896 if needed, but stay < 1GB overall.
ENV NODE_OPTIONS="--max-old-space-size=768"

# Copy only dependency manifests first for better Docker caching
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

# Install deps
RUN pnpm install --frozen-lockfile

# Copy the rest of the repo
COPY . .

# Give Node/tsc more heap during build to avoid OOM
ENV NODE_OPTIONS="--max-old-space-size=2048"

# Build backend
RUN CLAWDBOT_A2UI_SKIP_MISSING=1 pnpm build

# Build UI (force pnpm as you had)
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

# Prune to production deps only (smaller runtime + fewer issues)
RUN pnpm prune --prod


# -------------------------
# 2) Runtime stage
# -------------------------
FROM node:22-bookworm AS runtime

ENV NODE_ENV=production

# Use the existing 'node' user (uid 1000)
USER node
WORKDIR /app

# Copy only what we need from the builder
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# If your runtime also needs UI artifacts, copy them too.
# (Keep whichever paths exist in your repo after ui:build.)
COPY --from=builder /app/ui ./ui

# Railway will inject PORT. Your app should bind to 0.0.0.0:$PORT internally.
CMD ["node", "dist/index.js"]

