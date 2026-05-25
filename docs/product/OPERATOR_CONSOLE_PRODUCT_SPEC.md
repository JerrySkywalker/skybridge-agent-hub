# Operator Console Product Spec

SkyBridge Operator Console is the daily control surface for the agent-agnostic SkyBridge control plane. It is not a production deployment panel and does not expose raw prompts, command output, patches, secrets or public Hermes access.

## Product Surfaces

### Overview

Purpose: answer "what needs attention right now?"

Shows system health, active and failed runs, open PR count, latest CI state, latest auto-merge sweep, latest iteration, Hermes status, latest notification, recent failures and the next recommended operator action.

### Runs

Purpose: inspect agent work across planner, executor and runtime adapters such as Codex, OpenCode, Hermes and custom sources.

Shows run list, source, status, branch/goal metadata, tool counts, failed tools, latest safe summary and a run detail timeline.

### Iterations

Purpose: supervise bounded autonomous work loops.

Shows iteration state, PR number, branch, attempts, repair attempts, blocked reasons, checks and state-event timeline. Raw local logs remain outside the API.

### PR/CI

Purpose: review PR readiness without mutating GitHub settings.

Shows locally derived open PRs, required checks, latest CI state, eligibility, risk classifier output, blocked reasons and merged history when audit or iteration events exist.

### Auto-Merge

Purpose: make guarded auto-merge decisions reviewable.

Shows dry-run sweep status, eligible and blocked counts, classifier reasons, required checks and a clear reminder that auto-merge is disabled by default.

### Notifications

Purpose: verify operator alerting health.

Shows provider status, sent/skipped/failed/pending counts, severity distribution, bootstrap fallback status and troubleshooting links. Real delivery remains explicit and manual unless a future approved goal changes that boundary.

### Hermes Adapter

Purpose: summarize the optional private Hermes planner/supervisor adapter.

Shows local tunnel status, API health, capabilities, last safe run, nightly report summary, sweep dry-run summary and degraded reason. The UI must keep `public_exposure=false` and never publish Hermes.

### Adapter Registry

Purpose: show the Core + Adapter Ring boundary.

Shows planner adapters, executor adapters, SCM/CI providers, notification providers and runtime providers with stability, dogfooding and optionality metadata. Hermes, Codex, GitHub and ntfy appear as adapters/providers, not core services.

### Sources/Adapters

Purpose: explain where telemetry comes from.

Shows supported source platforms, adapters, capabilities, event counts and last-seen timestamps.

### Audit

Purpose: review safety-relevant actions.

Shows derived audit records for approvals, node telemetry, notification metadata and failures. Audit exports are local, bounded and raw-payload-free.

### Settings

Purpose: make local operation understandable.

Shows API base, persistence mode, docs links, smoke commands and safety boundaries. It must not display secret values.

## Product Data Contract

The console consumes safe server APIs:

- `GET /v1/summary`
- `GET /v1/projects`
- `GET /v1/iterations/summary`
- `GET /v1/prs/summary`
- `GET /v1/notifications/summary`
- `GET /v1/hermes/summary`
- `GET /v1/automerge/summary`
- `GET /v1/adapters`
- existing run, event, notification, audit, sources and node APIs

All derived summaries use already normalized `skybridge.agent_event.v1` events, durable iteration records, notification records and audit metadata.

## Safety

- No production deployment controls.
- No GitHub settings mutation.
- No always-on unattended auto-merge by default.
- No public Hermes exposure.
- No Hermes, Codex, GitHub or ntfy hard dependency in core product flows.
- No raw prompts, stdout, stderr, patches, tokens, cookies or secrets.
- Notification real sends stay behind explicit manual commands.
