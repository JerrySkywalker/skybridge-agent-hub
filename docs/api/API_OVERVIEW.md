# API Overview

## Edge Worker

The edge worker uses the existing Worker Pool and Task Queue APIs:

- `POST /v1/workers/register`
- `POST /v1/workers/:workerId/heartbeat`
- `GET /v1/tasks?status=queued&project_id=<project>`
- `POST /v1/tasks/:taskId/claim`
- `POST /v1/tasks/:taskId/start`
- `POST /v1/tasks/:taskId/complete`
- `POST /v1/tasks/:taskId/fail`

Codex execution, validation logs and raw command output stay local under `.agent/workers/<worker>/<task>/`. Task result payloads contain only safe summaries, local operator paths and optional PR URLs.

SkyBridge APIs are local-first and return safe derived metadata for an agent-agnostic control plane. They must not expose raw prompts, patches, stdout, stderr, tokens, cookies or production secrets.

## Product Summary APIs

- `GET /v1/summary`: top-level health, counts, latest states, recent failures and recommended action.
- `GET /v1/projects`: local project summaries derived from runs and iterations.
- `GET /v1/iterations/summary`: iteration counts, latest iteration, repair attempts and blocked reasons.
- `GET /v1/prs/summary`: local PR/CI summary derived from iteration records and safe events.
- `GET /v1/notifications/summary`: notification counts, provider state and bootstrap fallback status.
- `GET /v1/hermes/summary`: optional private Hermes adapter tunnel/API/capability status from local telemetry.
- `GET /v1/automerge/summary`: dry-run default, eligibility decisions, blocked reasons and local merged history when available.
- `GET /v1/adapters`: neutral planner, executor, SCM/CI, notification and runtime provider capability registry.

## Core APIs

- `GET /v1/health`
- `POST /v1/events`
- `GET /v1/events`
- `POST /v1/workers/register`
- `POST /v1/workers/:workerId/heartbeat`
- `GET /v1/workers`
- `GET /v1/workers/:workerId`
- `PATCH /v1/workers/:workerId`
- `GET /v1/workers/summary`
- `POST /v1/projects`
- `GET /v1/projects`
- `GET /v1/projects/:projectId`
- `POST /v1/projects/:projectId/goals`
- `GET /v1/projects/:projectId/goals`
- `GET /v1/goals/:goalId`
- `PATCH /v1/goals/:goalId`
- `POST /v1/tasks`
- `GET /v1/tasks`
- `GET /v1/tasks/:taskId`
- `POST /v1/tasks/:taskId/claim`
- `POST /v1/tasks/:taskId/start`
- `POST /v1/tasks/:taskId/complete`
- `POST /v1/tasks/:taskId/fail`
- `POST /v1/tasks/:taskId/block`
- `POST /v1/tasks/:taskId/requeue`
- `GET /v1/tasks/summary`
- `GET /v1/projects/:projectId/tasks`
- `GET /v1/runs`
- `GET /v1/runs/:runId`
- `GET /v1/iterations`
- `GET /v1/iterations/:iterationId`
- `GET /v1/notifications`
- `GET /v1/audit`
- `GET /v1/sources`
- `GET /v1/adapters`
- `GET /v1/nodes`
- `GET /v1/metrics`
- `GET /v1/approvals`
- `GET /v1/stream`

## Stability Notes

The product summary APIs are intended for dashboard and embed consumption. Field names use snake_case to match existing server responses. Derived PR, Hermes and auto-merge summaries are local/fixture-backed unless future integrations explicitly persist richer state. Hermes, Codex, GitHub and ntfy remain adapters/providers, not core API dependencies.

Remote execution and production deployment APIs are intentionally absent.

## Worker APIs

Workers are runtime providers such as a manual executor, Codex worker, OpenCode worker or future sidecar. `PATCH /v1/workers/:workerId` can update safe display metadata and the enabled flag. Worker status is derived from heartbeat recency and enabled state: `online`, `stale`, `offline` or `disabled`.

Worker responses do not include credentials or secret configuration.

## Project And Goal APIs

Projects contain master goals. Master goals are durable objectives that planner adapters can later decompose into tasks. Hermes may create goals or tasks through an adapter, but the APIs are neutral and also support manual or rule-based planners.

## Task APIs

Tasks move through this lifecycle:

```text
queued -> claimed -> running -> completed
queued -> claimed -> failed -> queued
queued -> blocked
```

Supported statuses are `queued`, `claimed`, `running`, `completed`, `failed`, `blocked`, `cancelled` and `stale`. Completed and cancelled tasks cannot be claimed again. Disabled or offline workers cannot claim tasks.

Task result fields are safe summaries and links only. Raw prompts, command output, patches, tokens and secrets must not be stored.

## Safety Notes

The Worker Pool and Task Queue APIs are local/control-plane state APIs. They do not start real Codex, OpenCode or Hermes execution, do not mutate GitHub settings and do not send notifications by themselves. Executor and planner behavior remains adapter-owned.
