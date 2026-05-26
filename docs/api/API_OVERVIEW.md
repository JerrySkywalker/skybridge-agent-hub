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

## PR Lifecycle Automation

PR lifecycle and merge coordination currently run through local automation scripts rather than server mutation APIs:

- `classify-skybridge-pr.ps1`: classifies child task, parent/super-goal, tracking, duplicate, stale, conflicting, high-risk, blocked and auto-merge-candidate PRs.
- `skybridge-merge-coordinator.ps1`: lists open PRs, applies per-project serial merge policy, recommends actions and defaults to dry-run.
- `build-planner-compact-state.ps1`: emits safe compact planner state for Hermes, including completed/open tasks, open/merged PRs, dedupe keys, changed files, CI status, auto-merge status, locked files and `do_not_repeat`.

Default policy:

- child task PR: auto PR plus auto-merge when eligible;
- parent/super-goal PR: auto PR plus manual merge unless a later policy explicitly allows low-risk parent auto-merge;
- high-risk PR: auto PR for human review only.

These scripts do not mutate GitHub settings or branch protection. `skybridge-merge-coordinator.ps1` mutates PRs only with `-Apply`.

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

Goals are now registry assets, not just labels for tasks. Supported registry metadata includes `source`, `priority`, `risk`, `status`, `lifecycle`, `acceptance_criteria`, `evidence_requirements`, `dedupe_key`, `supersedes`, `superseded_by`, `stale_reason`, `blocked_reason`, `planner_metadata`, optional audit-only `model_backend_metadata`, `completion_note`, `evidence_summary` and `progress_summary`.

Goal lifecycle statuses:

```text
draft
ready
queued
active
partially_completed
completed
failed
blocked
superseded
archived
paused
cancelled
```

Validation rules:

- archived and superseded goals cannot receive new executable tasks;
- blocked goals require `blocked_reason`;
- completed goals require `completion_note` or an evidence summary;
- superseded goals require `superseded_by` to reference an existing goal.

`GET /v1/projects/:projectId/goals` and `GET /v1/goals/:goalId` include a `task_summary` object with queued/running/completed/failed/blocked counts plus evidence count. Task completion may include an `evidence_summary`; SkyBridge copies the latest summary to the goal and updates `progress_summary`. It does not auto-complete the goal.

Markdown import/export is script-based:

- `scripts/powershell/import-goal-markdown.ps1`
- `scripts/powershell/export-goal-markdown.ps1`

## Task APIs

Tasks move through this lifecycle:

```text
queued -> claimed -> running -> completed
queued -> claimed -> failed -> queued
queued -> blocked
```

Supported statuses are `queued`, `claimed`, `running`, `completed`, `failed`, `blocked`, `cancelled` and `stale`. Completed and cancelled tasks cannot be claimed again. Disabled or offline workers cannot claim tasks.

Task result fields are safe summaries and links only. Raw prompts, command output, patches, tokens and secrets must not be stored.

`POST /v1/tasks/:taskId/complete` accepts an optional `evidence_summary` with `task_id`, `goal_id`, `pr_url`, `commit_sha`, `changed_files`, `validation_status`, `ci_status`, `risk_status`, `summary` and `created_at`.

## Safety Notes

The Worker Pool and Task Queue APIs are local/control-plane state APIs. They do not start real Codex, OpenCode or Hermes execution, do not mutate GitHub settings and do not send notifications by themselves. Executor and planner behavior remains adapter-owned.
