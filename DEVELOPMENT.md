# Development Guide

## Prerequisites

Recommended tools:

- PowerShell 7+
- Git
- Node.js LTS
- pnpm via Corepack
- Docker Desktop
- GitHub CLI
- Codex CLI
- optional: just

## Setup

```powershell
cd V:\src\skybridge-agent-hub
corepack enable
pnpm install
```

## Run locally

```powershell
pnpm dev
```

For focused development:

```powershell
pnpm --filter @skybridge-agent-hub/server dev
pnpm --filter @skybridge-agent-hub/web dev
```

Useful environment variables:

```text
PORT=8787
HOST=0.0.0.0
SKYBRIDGE_DATA_FILE=.data/skybridge-store.json
SKYBRIDGE_PUBLIC_URL=http://127.0.0.1:3000
NTFY_TOPIC_URL=https://ntfy.sh/example-topic
NTFY_TOKEN=
VITE_SKYBRIDGE_API_BASE=http://127.0.0.1:8787
```

Or start services with Docker:

```powershell
docker compose -f deploy/docker-compose.dev.yml up --build
```

Check compose without starting services:

```powershell
docker compose -f deploy/docker-compose.dev.yml config
docker compose -f deploy/docker-compose.test.yml config
```

## Standard checks

```powershell
pnpm lint
pnpm typecheck
pnpm test
pnpm build
```

## Goal-driven development

Use:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-goal.ps1 `
  -GoalFile .\goals\ready\001-yolo-guardrails.md
```

## Thesis YOLO runner

Use:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -Mode ThesisYOLO `
  -MaxRepairRounds 3 `
  -NotifyOnlyImportant:$true
```

Start with `-AutoPR:$false` and `-AutoMergeLowRisk:$false`.
