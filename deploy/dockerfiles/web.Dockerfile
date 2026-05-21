FROM node:22-bookworm-slim AS deps

WORKDIR /workspace
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/web/package.json apps/web/package.json
COPY packages/client/package.json packages/client/package.json
COPY packages/event-schema/package.json packages/event-schema/package.json
COPY packages/react-widgets/package.json packages/react-widgets/package.json
RUN pnpm install --frozen-lockfile=false

FROM deps AS build
COPY tsconfig.base.json ./
COPY apps/web apps/web
COPY packages/client packages/client
COPY packages/event-schema packages/event-schema
COPY packages/react-widgets packages/react-widgets
RUN pnpm --filter @skybridge-agent-hub/web build

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production \
    VITE_SKYBRIDGE_API_BASE=http://127.0.0.1:8787
WORKDIR /workspace
RUN corepack enable
COPY --from=build /workspace /workspace
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD node -e "fetch('http://127.0.0.1:3000/').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["pnpm", "--filter", "@skybridge-agent-hub/web", "start"]
