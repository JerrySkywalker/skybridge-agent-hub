FROM node:22-bookworm-slim AS deps

WORKDIR /workspace
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/server/package.json apps/server/package.json
COPY packages/event-schema/package.json packages/event-schema/package.json
COPY packages/notification-providers/ntfy/package.json packages/notification-providers/ntfy/package.json
RUN pnpm install --frozen-lockfile=false

FROM deps AS build
COPY tsconfig.base.json ./
COPY apps/server apps/server
COPY packages/event-schema packages/event-schema
COPY packages/notification-providers/ntfy packages/notification-providers/ntfy
RUN pnpm --filter @skybridge-agent-hub/server build

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=8787 \
    SKYBRIDGE_DB_FILE=/app/data/skybridge.sqlite
WORKDIR /workspace
RUN corepack enable && mkdir -p /app/data
COPY --from=build /workspace /workspace
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 8787) + '/health').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["pnpm", "--filter", "@skybridge-agent-hub/server", "start"]
