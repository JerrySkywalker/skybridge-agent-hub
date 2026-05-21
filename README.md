# SkyBridge Agent Hub

SkyBridge Agent Hub is a long-term, open-source control and telemetry foundation for Jerry's local and cloud AI agents.

It is designed to bridge:

- local Codex CLI / Codex exec / Codex app-server workflows;
- OpenCode plugin events;
- Hermes Agent runs and status events;
- a reusable notification center based on ntfy first, extensible to Apprise, FCM, Xiaomi Push, WeCom, Bark and Gotify later;
- embeddable dashboard widgets for Glance, standalone web dashboards and future remote-control apps.

The previous starter name intentionally avoided becoming the long-term identity. This package now uses the long-lived project name:

```text
Product: SkyBridge Agent Hub
Repo/folder: skybridge-agent-hub
NPM scope: @skybridge-agent-hub/*
Event schema: skybridge.agent_event.v1
Default local path: V:\src\skybridge-agent-hub
Default deploy path: /opt/skybridge-agent-hub
```

## Extract location

Recommended path:

```powershell
V:\src\skybridge-agent-hub
```

If this zip creates a top-level folder automatically, extract it under `V:\src`.

SQLite persistence uses Node's built-in `node:sqlite` module. Use Node.js 22.5+ for local server development.

## First local commands

```powershell
cd V:\src\skybridge-agent-hub
pnpm install
pnpm check
```

Start the MVP locally:

```powershell
pnpm --filter @skybridge-agent-hub/server dev
pnpm --filter @skybridge-agent-hub/web dev
```

The server listens on `http://127.0.0.1:8787` by default and exposes `GET /health`, `POST /v1/events`, `GET /v1/events`, `GET /v1/runs`, `GET /v1/stream` and `POST /v1/notifications/send`.

Events and notification attempts are persisted to `.data/skybridge.sqlite` unless `SKYBRIDGE_DB_FILE` is set. On first SQLite startup, the server safely imports an existing `.data/skybridge-store.json` or `SKYBRIDGE_DATA_FILE` file if present; the JSON file is left in place as a rollback copy. ntfy is optional; set `NTFY_TOPIC_URL` and, if required, `NTFY_TOKEN`.

If `pnpm` or `just` is not ready yet, start with the goal files instead:

```powershell
Get-Content .\goals\00_MASTER_GOAL.md
Get-Content .\goals\ready\001-yolo-guardrails.md
```

## Codex goal-mode entry

Use the prepared one-shot helper:

```powershell
.\scripts\powershell\run-goal.ps1 -Goal .\goals\ready\001-yolo-guardrails.md
```

For thesis-defense low-intervention development:

```powershell
.\scripts\powershell\yolo-runner.ps1 `
  -Mode ThesisYOLO `
  -MaxRepairRounds 3 `
  -AutoPR `
  -NotifyOnlyImportant
```

The runner is intentionally a starter scaffold. Let Codex harden it through the staged goal files.

## Current architecture target

```text
Codex / OpenCode / Hermes
        │
        ▼
Local Sidecar / Hook Adapters
        │
        ▼
SkyBridge Server
  - event ingestion
  - run/session state
  - SSE stream
  - notification jobs
        │
        ├── Dashboard widgets
        └── Message Center → ntfy first, more push providers later
```

## What is implemented now

The MVP foundation covers the first staged goals and several follow-up slices:

1. YOLO guardrails and project rules;
2. pnpm TypeScript monorepo bootstrap;
3. `skybridge.agent_event.v1` schema and tests;
4. server health, event ingestion, event list, run summaries and SSE stream;
5. SQLite persistence for MVP history with one-time local JSON migration;
6. React dashboard shell and reusable widgets;
7. Web Component status card;
8. Codex hook adapter and safety guard scripts;
9. local sidecar forwarder;
10. ntfy-first notification provider with placeholder behavior when credentials are missing;
11. Docker dev/test compose files and public PR CI.

After those pass, move files from `goals/backlog` into `goals/ready` as needed.

## Safety stance

SkyBridge is meant to support high-autonomy development, not uncontrolled production access.

Default rule:

```text
AI may develop aggressively inside branches, worktrees and containers.
AI must not silently change secrets, production deployment files or server root-level configuration.
```

See `AGENTS.md`, `SECURITY.md`, `docs/codex/GOAL_MODE.md` and `docs/operations/DEPLOYMENT.md`.
