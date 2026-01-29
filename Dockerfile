# ---------- builder ----------
FROM node:22-bookworm AS builder

# Make pnpm available via corepack
RUN corepack enable && corepack prepare pnpm@10.23.0 --activate

# CI mode prevents pnpm prune from requiring a TTY
ENV CI=true

# Put caches in writable temp locations
ENV NPM_CONFIG_CACHE=/tmp/.npm
ENV XDG_CACHE_HOME=/tmp/.cache
ENV PNPM_HOME=/tmp/.pnpm
ENV PATH="/tmp/.pnpm:${PATH}"

WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .

# If you still OOM here, you simply need a bigger builder (see note below)
ENV NODE_OPTIONS="--max-old-space-size=2048"

RUN CLAWDBOT_A2UI_SKIP_MISSING=1 pnpm build

# Force pnpm for UI build
ENV CLAWDBOT_PREFER_PNPM=1
RUN pnpm ui:install
RUN pnpm ui:build

# Prune dev deps for runtime image
RUN pnpm prune --prod

# ---------- runtime ----------
FROM node:22-bookworm-slim AS runtime

ENV NODE_ENV=production
ENV NPM_CONFIG_CACHE=/tmp/.npm
ENV XDG_CACHE_HOME=/tmp/.cache

WORKDIR /app

# Copy built app + prod deps
COPY --from=builder /app /app

# Run as non-root
USER node

CMD ["node", "dist/index.js"]

