FROM node:22-bookworm

WORKDIR /workspace
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile=false
EXPOSE 8787
CMD ["pnpm", "--filter", "@skybridge-agent-hub/server", "dev"]
