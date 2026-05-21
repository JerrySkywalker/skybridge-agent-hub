# SkyBridge Operator Console

## Purpose

The SkyBridge Operator Console is the local-first dashboard for supervising autonomous agent development. It should help an operator answer four questions quickly:

- Is SkyBridge receiving telemetry?
- What agents and runs are active or recently failed?
- What needs attention now?
- Is the Codex local integration healthy enough to trust during long unattended work?

The console is not a marketing page and is not a remote-control surface yet. It is an operational view over already-redacted `skybridge.agent_event.v1` events, run summaries, notification records and the live SSE stream.

## Target Users

- Jerry during thesis-defense YOLO mode, supervising long-running Codex and runner work with minimal interruptions.
- Future maintainers reviewing local development health before opening or reviewing AI-generated pull requests.
- Integrators embedding a compact SkyBridge status card in local dashboards such as Glance.

## Page Structure

The minimum usable console contains these sections:

1. **System health**: API availability, persistence mode, server time and live stream state.
2. **Active/recent runs**: scan-friendly run rows with status, source, branch, goal, tool counts and latest activity.
3. **Event timeline**: recent normalized events with source/platform filters, severity, type and correlation IDs.
4. **Codex integration status**: Codex hook and exec activity, active/failed tools, spool/replay hints when events include spool metadata.
5. **Notifications/attention queue**: failed runs, approval requests and notification send/skipped/failed records.
6. **Source/platform filters**: platform, adapter, severity, type and free text/correlation filters shared across panels where practical.
7. **Run detail view**: summary plus recent events for one run, using only safe metadata returned by the API.
8. **Compact embed view**: a narrow status card suitable for embedding in an HTML dashboard.

## Key Panels

### System Health

Data dependencies:

- `GET /health` or `GET /v1/health`
- `GET /v1/stream`

States:

- Loading: show a small loading state while the health request is pending.
- Healthy: show persistence, server time and stream connection state.
- Offline/error: show the failed API base and a concise error message without stack traces.

### Active And Recent Runs

Data dependencies:

- `GET /v1/runs`
- optional filters: `platform`, `adapter`, `status`, `branch`, `goal`, `from`, `to`, `limit`

States:

- Empty: no runs match the current filters.
- Loading: first load is pending.
- Error: API failure, keeping the previous run list visible when available.

### Event Timeline

Data dependencies:

- `GET /v1/events`
- `GET /v1/stream`
- filters: `platform`, `adapter`, `run_id`, `session_id`, `type`, `severity`, `from`, `to`, `limit`, and offset/cursor when available.

States:

- Empty: no events match the current filters.
- Live: connected and appending incoming SSE events.
- Reconnecting/offline: keep the current list, show stream state, cap the rendered list length.

### Codex Integration Status

Data dependencies:

- Codex events from `/v1/events`
- Codex run summaries from `/v1/runs`
- optional spool count metadata in Codex hook events

The panel should distinguish `codex-hook` and `codex-exec-json` activity and emphasize failed tools, approval requests and stale/no-event states.

### Notifications And Attention Queue

Data dependencies:

- `GET /v1/notifications`
- failed run and approval events from `/v1/events`

The queue should treat skipped placeholder notifications as useful local evidence when ntfy is not configured, not as a dashboard crash.

### Run Detail View

Data dependencies:

- `GET /v1/runs/:runId`

The detail view should show the summary, safe metadata, latest message summary and recent events. It must not expose raw command output, prompts, secrets or unbounded payloads.

## Compact Embed Mode

The compact mode should work as:

- a web app route such as `/embed/compact` or a hash route;
- a framework-neutral Web Component such as `<agent-status-card api-base="http://127.0.0.1:8787" compact></agent-status-card>`.

It should display health, active/failed run counts, last event and offline state in a narrow card without depending on the full dashboard shell.

## Known Limitations

- The console depends on normalized event payloads and cannot reconstruct missing correlation IDs.
- Spool and replay status is visible only when adapters emit safe spool metadata.
- The current remote-control model is intentionally out of scope.
- Browser screenshot automation may not always be available in Codex sessions; local build and HTTP smoke scripts are the fallback validation path.
