FROM node:22-bookworm

WORKDIR /workspace
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile=false
EXPOSE 3000
CMD ["pnpm", "--filter", "@skybridge-agent-hub/web", "dev"]
