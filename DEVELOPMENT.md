# Development Guide

## Prerequisites

Recommended tools:

- PowerShell 7+
- Git
- Node.js 22.5+ with built-in `node:sqlite` support
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
SKYBRIDGE_DB_FILE=.data/skybridge.sqlite
SKYBRIDGE_DATA_FILE=.data/skybridge-store.json  # optional legacy JSON migration source
SKYBRIDGE_PUBLIC_URL=http://127.0.0.1:3000
NTFY_TOPIC_URL=https://ntfy.sh/example-topic
NTFY_TOKEN=
VITE_SKYBRIDGE_API_BASE=http://127.0.0.1:8787
```

By default, local server persistence uses repository-root `.data/skybridge.sqlite`, even when the server is started through a package script from `apps/server`. Set `SKYBRIDGE_DB_FILE` to override the SQLite file. `SKYBRIDGE_DATA_FILE` remains an optional legacy JSON migration source and defaults to repository-root `.data/skybridge-store.json`.

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

## Self-observation smoke

Start the local server, then send representative local-loop telemetry:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-observation.ps1 `
  -ApiBase http://127.0.0.1:8787
```

The script posts `skybridge.agent_event.v1` events from the `self-observation-smoke` adapter, verifies `/v1/runs/:runId`, verifies `/v1/events?run_id=...` and reports notification placeholder state. Use `-IncludeFailure` to simulate a redacted failed run for dashboard and notification checks.

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
