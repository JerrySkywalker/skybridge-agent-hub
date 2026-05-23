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

## Operator Console workflow

Use the Operator Console while developing telemetry, adapters, notifications or dashboard widgets:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
```

Open the Vite URL and use the console sections for health, runs, timeline, Codex integration, notifications and run detail. The compact iframe-style route is available at `/#/embed/compact`.

Focused checks:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server test
corepack pnpm --filter @skybridge-agent-hub/client test
corepack pnpm --filter @skybridge-agent-hub/react-widgets test
corepack pnpm --filter @skybridge-agent-hub/web-components test
corepack pnpm --filter @skybridge-agent-hub/web build
corepack pnpm smoke:operator-console
```

Nightly local validation for release-readiness:

```powershell
corepack pnpm nightly:local-validation
```

The nightly script runs safe local checks, smoke tests and optional local Docker builds, then writes `docs/dev/NIGHTLY_CICD_LOG.md`. It uses temporary databases and local dry-run paths; it does not deploy or read production secrets.

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

## Smoke script safety

Validation wrapper scripts named `smoke-*` should be safe by default and must not perform production actions unless an operator explicitly configures that behavior. Wrappers that validate dry-run capable automation should accept `-DryRun` even when their default behavior is already dry-run-only, so direct CLI use and package scripts stay consistent.

## Self-observation smoke

Start the local server, then send representative local-loop telemetry:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-observation.ps1 `
  -ApiBase http://127.0.0.1:8787
```

The script posts `skybridge.agent_event.v1` events from the `self-observation-smoke` adapter, verifies `/v1/runs/:runId`, verifies `/v1/events?run_id=...` and reports notification placeholder state. Use `-IncludeFailure` to simulate a redacted failed run for dashboard and notification checks.

## Operator Console demo data

With a local server running, seed realistic redacted dashboard data:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\seed-demo-events.ps1 `
  -ApiBase http://127.0.0.1:8787
```

For an isolated demo database, let the script start a temporary SQLite-backed server:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\seed-demo-events.ps1 `
  -UseTempDatabase
```

The fixture includes Codex hook, Codex exec, yolo-runner, failed tool, approval request, notification skipped/sent and offline spool/replay events. Payloads are intentionally fake and redacted.

## Codex hook integration smoke

Run the fixture-only hook test without a server. This should create redacted normalized audit and queue JSONL under a temporary spool directory:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\test-codex-hook-event.ps1 -RequireSpool
```

With the server running, validate online delivery plus offline spool replay:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-hook-integration.ps1 `
  -ApiBase http://127.0.0.1:8787
```

If no server is running, use an alternate local port and let the smoke script start a temporary server:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-hook-integration.ps1 `
  -ApiBase http://127.0.0.1:8798 `
  -StartServer
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
