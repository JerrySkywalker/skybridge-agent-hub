# SkyBridge Agent Hub

Open-source telemetry, notifications and control foundations for autonomous coding agents.

SkyBridge Agent Hub collects normalized events from tools such as Codex, OpenCode, Hermes Agent and future custom agents, then turns them into run state, dashboards, notification jobs and eventually safe remote-control workflows.

## Why SkyBridge Exists

Autonomous agents are useful, but their execution state is usually scattered across terminal logs, local hooks, CI output and ad hoc notification scripts. That makes long-running work hard to supervise and hard to recover when a run fails.

SkyBridge provides a shared foundation for:

- ingesting events from multiple agent runtimes;
- viewing sessions, runs, tool calls and failures in one place;
- sending low-noise notifications for important state changes;
- embedding agent status in React apps, web dashboards and Web Components;
- building toward local sidecars and remote approval/control surfaces without exposing secrets by default.

## Features

- Unified `skybridge.agent_event.v1` event schema.
- HTTP event ingestion and query APIs.
- Run/session aggregation for agent work history.
- Server-sent events stream for live dashboards.
- SQLite persistence with a one-time import path from the previous local JSON store.
- ntfy-first notification provider with skipped placeholder records when credentials are not configured.
- Codex hook adapter, OpenCode/Hermes adapter foundations and local sidecar event forwarder.
- React dashboard shell, reusable React widgets and a framework-neutral status Web Component.
- Productized Operator Console for daily agent operations across overview, runs, iterations, PR/CI, auto-merge, notifications, Hermes, sources, audit and compact embeds.
- Codex TUI Master Goal workflow for long-horizon autonomous development.
- PowerShell goal runner scripts for fallback queue-driven batch work.
- Public GitHub Actions checks for AI branches and pull requests.
- Reproducible Docker builds, GHCR publishing, release-tag validation, staging dry-run and backup/rollback operator scripts.
- Approval queue, node registry, metrics endpoint, demo dataset and release candidate smoke foundations.
- Nightly local validation script and release-candidate audit docs for repeatable v0.9 hardening.
- Agent CI/CD Control Plane foundations: Autonomous Iteration Controller, CI Guardian, Hermes supervisor bridge, bootstrap direct notifications and iteration dashboard panels.

## Current MVP Status

SkyBridge is in an MVP foundation stage. The repository already contains:

- a pnpm TypeScript monorepo;
- `apps/server` for event ingestion, run summaries, notifications and SSE;
- `apps/web` for the local dashboard;
- `packages/event-schema`, `packages/client`, `packages/agent-adapters`, `packages/react-widgets`, `packages/web-components` and `packages/notification-providers`;
- Docker dev/test compose files;
- Codex TUI Master Goal files plus runner scripts for fallback local batch processing.

The remote-control surface is intentionally not production-ready yet. Current work focuses on local-first telemetry, notification, reviewable AI branches and safe iteration.
The v0.9 release-candidate track adds multi-agent adapters, sidecar node identity, provider/rule notification records, approval queue APIs and security hardening while keeping remote execution disabled. OpenCode and Hermes compatibility is fixture-backed until real runtime contract tests are added.

## Quick Start

Requirements:

- PowerShell 7+
- Git
- Node.js 22.5+ with `node:sqlite`
- pnpm via Corepack
- optional: Docker, GitHub CLI, Codex CLI and `just`

Install and check the workspace:

```powershell
corepack enable
corepack pnpm install
corepack pnpm check
```

Start the local server and web dashboard:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
```

The server listens on `http://127.0.0.1:8787` by default. Events and notification attempts are persisted to `.data/skybridge.sqlite` unless `SKYBRIDGE_DB_FILE` is set.

### Operator Console

The web dashboard is the SkyBridge Operator Console. It shows system health, active/recent runs, iterations, PR/CI state, auto-merge decisions, notification health, Hermes supervision, source adapters, audit metadata and a safe run detail panel.

Seed a local demo view:

```powershell
corepack pnpm --filter @skybridge-agent-hub/web build
corepack pnpm smoke:operator-console
corepack pnpm smoke:product-console
```

For interactive development, start the server and web app, then optionally seed demo events:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
corepack pnpm --filter @skybridge-agent-hub/web dev
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\seed-demo-events.ps1
```

Compact embed route:

```text
http://127.0.0.1:5173/#/embed/compact
```

See [docs/ui/OPERATOR_CONSOLE.md](docs/ui/OPERATOR_CONSOLE.md) and [docs/ui/EMBEDDING.md](docs/ui/EMBEDDING.md).
See also [docs/product/QUICKSTART_DASHBOARD.md](docs/product/QUICKSTART_DASHBOARD.md), [docs/product/OPERATOR_CONSOLE_PRODUCT_SPEC.md](docs/product/OPERATOR_CONSOLE_PRODUCT_SPEC.md), [docs/product/SCREENSHOT_GUIDE.md](docs/product/SCREENSHOT_GUIDE.md) and [docs/api/API_OVERVIEW.md](docs/api/API_OVERVIEW.md).

### Demo Dataset

Generate safe multi-agent demo data:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\generate-demo-dataset.ps1
```

See [docs/demo/DEMO_DATASET.md](docs/demo/DEMO_DATASET.md).

### Codex Hook Integration

Validate the local Codex hook path without changing user config:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\test-codex-hook-event.ps1 -RequireSpool
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-hook-integration.ps1 `
  -ApiBase http://127.0.0.1:8787
```

Preview user-level Codex hook installation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\install-codex-hooks.ps1
```

The installer is dry-run by default and writes `~/.codex/hooks.json` only with `-Apply`, backing up an existing file first. Hook delivery is fail-open: if SkyBridge is offline, normalized redacted events queue under `.agent/spool/codex-hook` or `SKYBRIDGE_CODEX_SPOOL_DIR`.

Replay queued hook events after the server returns:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\replay-codex-hook-spool.ps1
```

See [docs/codex/CODEX_LOCAL_INTEGRATION.md](docs/codex/CODEX_LOCAL_INTEGRATION.md) and [docs/codex/HOOKS.md](docs/codex/HOOKS.md).

## Architecture

```text
Agent Sources
  Codex hooks / Codex exec JSON / Codex app-server
  OpenCode plugin events
  Hermes Agent API/events
  Custom agents
        |
        v
Adapter Layer
  Normalize source-specific events
        |
        v
SkyBridge Server
  Event ingestion
  Run/session aggregation
  SSE/WebSocket stream
  Notification job creation
        |
        +-- Dashboard widgets
        +-- Message center
        +-- Future remote app API
```

The server is the durable local/cloud hub. Adapters are responsible for turning source-specific payloads into the normalized event schema before the data reaches server APIs or UI packages.

## Event Model

All adapters emit `skybridge.agent_event.v1`. Supported event families include:

```text
session.*
run.*
turn.*
plan.*
todo.*
tool.*
file.*
diff.*
approval.*
message.*
agent.*
notification.*
```

Events include source metadata, optional run/session correlation IDs, severity and a redacted payload. Codex hook payloads intentionally summarize tool input and omit full command output by default.

## API Examples

Check server health:

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health
```

Ingest an event:

```powershell
$event = @{
  schema = "skybridge.agent_event.v1"
  id = "evt_demo_001"
  type = "run.started"
  source = @{
    kind = "codex"
    id = "local-codex"
  }
  occurredAt = (Get-Date).ToUniversalTime().ToString("o")
  severity = "info"
  run = @{
    id = "run_demo_001"
    title = "Demo run"
  }
  payload = @{
    message = "A demo run started."
  }
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8787/v1/events `
  -ContentType "application/json" `
  -Body $event
```

List recent events and run summaries:

```powershell
Invoke-RestMethod http://127.0.0.1:8787/v1/events
Invoke-RestMethod http://127.0.0.1:8787/v1/runs
Invoke-RestMethod http://127.0.0.1:8787/v1/runs/run_demo_001
Invoke-RestMethod "http://127.0.0.1:8787/v1/events?run_id=run_demo_001"
Invoke-RestMethod "http://127.0.0.1:8787/v1/runs?platform=codex&status=failed"
Invoke-RestMethod "http://127.0.0.1:8787/v1/summary"
Invoke-RestMethod "http://127.0.0.1:8787/v1/sources"
Invoke-RestMethod "http://127.0.0.1:8787/v1/nodes"
Invoke-RestMethod "http://127.0.0.1:8787/v1/metrics"
Invoke-RestMethod "http://127.0.0.1:8787/v1/audit"
Invoke-RestMethod "http://127.0.0.1:8787/v1/approvals"
```

Send a notification request:

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri http://127.0.0.1:8787/v1/notifications/send `
  -ContentType "application/json" `
  -Body (@{
    title = "SkyBridge"
    message = "Notification smoke test"
    priority = "default"
  } | ConvertTo-Json)
```

## Local Development

Preferred commands:

```powershell
just check
just dev
just test
just build
```

Fallback commands when `just` is not installed:

```powershell
corepack pnpm lint
corepack pnpm typecheck
corepack pnpm test
corepack pnpm build
corepack pnpm check
```

Run Docker checks:

```powershell
docker compose -f deploy/docker-compose.dev.yml config
docker compose -f deploy/docker-compose.test.yml config
docker compose -f deploy/docker-compose.prod.yml config
corepack pnpm smoke:release-dry-run
```

## Release And Deployment Scope

SkyBridge has public CI for pull requests, AI branches, Docker image builds, GHCR publishing and tag validation. Public PRs run only on GitHub-hosted runners and do not receive production secrets or privileged deployment access.

Release images publish to GHCR on `main` and `v*` tags. Staging automation is dry-run only: it validates image tags, env file presence and rendered compose config without starting containers or touching real servers. Real deployment remains a separate operator action.

See [docs/operations/CI_CD_RELEASE_PLAN.md](docs/operations/CI_CD_RELEASE_PLAN.md), [docs/operations/RELEASE.md](docs/operations/RELEASE.md), [docs/operations/DEPLOYMENT.md](docs/operations/DEPLOYMENT.md) and [docs/operations/BACKUP_ROLLBACK.md](docs/operations/BACKUP_ROLLBACK.md).

## Autonomous Development Workflows

Recommended primary workflow:

1. Use Codex TUI for long-horizon development.
2. Read `goals/00_AUTONOMOUS_MASTER_GOAL.md`.
3. Select one `goals/mega/*.md` goal.
4. Work staged sub-goals in order, committing each coherent passing stage.
5. Run `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

Start Codex TUI:

```powershell
codex
```

Then start the first mega goal with:

```text
/goal Execute Mega Goal 001 from goals/mega/001-self-observable-skybridge-loop.md.

Read AGENTS.md, goals/00_AUTONOMOUS_MASTER_GOAL.md, docs/codex/TUI_MASTER_GOAL.md and the goal file first. Work one staged sub-goal at a time, make coherent commits, run focused checks before commits, run just check before stopping, push the branch, and do not cross the safety boundaries.
```

Use the local runner for bounded batch/background tasks that are already decomposed into `goals/ready/*.md` files. The runner is intentionally single-worker and must keep `MaxParallel` at `1`.

Validate the local self-observation loop after starting the server:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-observation.ps1 `
  -ApiBase http://127.0.0.1:8787
```

The smoke script sends redacted representative runner events, verifies the run detail API, verifies scoped event queries and records notification placeholder behavior when ntfy is not configured.

Run one queued goal with the fallback runner path:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-goal.ps1 `
  -GoalFile .\goals\ready\001-yolo-guardrails.md
```

Run the fallback local batch queue:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -ConfigFile .\config\runner.example.json
```

Use `codex exec` for CI/scripted one-shot tasks, repair loops and non-interactive automation where a TUI session is unnecessary.

### Agent CI/CD Control Plane

SkyBridge now includes a reusable Agent CI/CD Control Plane foundation:

- `skybridge-iterate.ps1` runs one bounded autonomous iteration from a goal file or queue.
- `skybridge-ci-guardian.ps1` watches and repairs PR CI without merging by default.
- `skybridge-hermes-supervisor.ps1` gives Hermes a JSON bridge for status, start-next, repair and nightly reports.
- `notify-bootstrap.ps1` sends direct ntfy or urgent WeCom/WeChat notifications without depending on the SkyBridge server.
- Hermes cloud supervision can be validated through a local SSH tunnel with redacted API, run, supervisor and phone-notification smokes.
- The nightly autonomy pilot verifies or starts the private Hermes tunnel, checks Hermes health, produces a nightly report, runs an auto-merge sweep dry-run and can send one non-urgent phone summary when explicitly requested.

Start with dry runs:

```powershell
corepack pnpm smoke:iteration-controller
corepack pnpm smoke:ci-guardian
corepack pnpm smoke:hermes-supervisor-flow
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-api.ps1 -DryRun -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-supervised-sweep.ps1 -DryRun -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-hermes-nightly-pilot.ps1 -UseHermesApi -Json
```

See [docs/automation/AUTONOMOUS_ITERATION_CONTROLLER.md](docs/automation/AUTONOMOUS_ITERATION_CONTROLLER.md), [docs/hermes/SUPERVISOR.md](docs/hermes/SUPERVISOR.md), [docs/hermes/CLOUD_SUPERVISOR_RUNBOOK.md](docs/hermes/CLOUD_SUPERVISOR_RUNBOOK.md) and [docs/automation/REUSABLE_PROJECT_INTEGRATION.md](docs/automation/REUSABLE_PROJECT_INTEGRATION.md).

Current responsibility split:

- local Windows/Codex worker: edits code, runs checks, opens AI branches and executes pilot scripts;
- GitHub: runs CI, enforces branch protection and performs auto-merge only when explicitly enabled for eligible low-risk PRs;
- auto-merge sweep: classifies open PRs and defaults to dry-run;
- cloud Hermes: supervises through the private tunnel and reports health/capabilities;
- bootstrap ntfy: sends concise fallback phone summaries without requiring the SkyBridge server;
- human-only: production deployment, server root configuration, branch protection changes, secret rotation, public Hermes exposure and unattended real auto-merge enablement.

## Roadmap

- Complete the v0.9 release candidate in [ROADMAP.md](ROADMAP.md).
- Implement real WSS remote node transport behind auth, approval and audit boundaries.
- Improve dashboard filtering, compact views and notification history.
- Expand Web Component and React widget integration examples.
- Add browser visual QA and public documentation site packaging.

## Security Stance

SkyBridge is built for high-autonomy development, not silent production access.

- Do not commit `.env` files, tokens, keys, cookies or production credentials.
- Codex hooks and adapters must redact sensitive payloads by default.
- Production deployment, server root configuration and secret changes are outside the default autonomous workflow.
- PR and AI-branch CI use GitHub-hosted runners and should not require production secrets.
- Public PR automation must not run privileged self-hosted deployment jobs.

See [SECURITY.md](SECURITY.md), [AGENTS.md](AGENTS.md) and [docs/codex/GOAL_MODE.md](docs/codex/GOAL_MODE.md) for the full operating rules.

## Contributing

Contributions are welcome. Keep changes reviewable and include:

- a short summary of the behavior change;
- tests or a clear explanation when tests are not practical;
- risk level and rollback notes for PRs;
- related goal file or issue when applicable.

Use branch names such as `feat/<topic>`, `fix/<topic>` or `ai/<goal-id>-<slug>`. See [CONTRIBUTING.md](CONTRIBUTING.md) for PR conventions and labels.
