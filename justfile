set shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

install:
    corepack pnpm install

lint:
    corepack pnpm lint

typecheck:
    corepack pnpm typecheck

test:
    corepack pnpm test

build:
    corepack pnpm build

check:
    corepack pnpm check

dev:
    corepack pnpm dev

docker-dev:
    docker compose -f deploy/docker-compose.dev.yml up --build

docker-test:
    docker compose -f deploy/docker-compose.test.yml up --build --abort-on-container-exit
