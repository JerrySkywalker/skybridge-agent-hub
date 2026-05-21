# Self-Observation Loop

SkyBridge can observe its own autonomous development workflow by sending local Codex, runner and smoke-test activity through the same `skybridge.agent_event.v1` ingestion path used by external agents.

## Local Loop

```text
Codex hook events
Codex exec JSON events
PowerShell runner telemetry
Manual smoke events
        |
        v
First-party adapters / runner event builder
        |
        v
POST /v1/events
        |
        v
SQLite event store
        |
        +-- GET /v1/events
        +-- GET /v1/events?run_id=<id>
        +-- GET /v1/runs
        +-- GET /v1/runs/:runId
        +-- GET /v1/stream
        +-- notification placeholder or ntfy send
        |
        v
React widgets and dashboard
```

## Event Sources

| Source | Adapter | Typical events | Correlation |
| --- | --- | --- | --- |
| Codex hooks | `codex-hook` | `session.started`, `run.started`, `tool.started`, `tool.completed`, `approval.requested`, `turn.completed` | Codex `session_id`, `run_id`, `turn_id`, `tool_call_id` when available. Falls back to grouping by session in server summaries. |
| Codex exec JSON | `codex-exec-json` | `message.completed`, `run.completed`, `run.failed` | `session_id` and `run_id` when present in the JSON stream. |
| Local runner | `yolo-runner` | `agent.idle`, `run.started`, `tool.started`, `tool.completed`, `tool.failed`, `run.completed`, `run.failed`, `notification.requested` | `run_id = runner-<goal-file-base>`, `session_id = runner-<pid>`, per-command `tool_call_id`. |
| Manual smoke | `self-observation-smoke` | Representative run, tool and notification trigger events | Stable demo run/session IDs for repeatable local validation. |

## Redaction Defaults

The loop must not upload full prompts, stdout, stderr, JSONL logs, `.env` contents, tokens or secrets by default.

Safe payloads include:

- lifecycle names;
- event source and adapter names;
- goal IDs and branch names;
- run/session/tool IDs;
- command names and exit codes;
- output length or presence flags;
- explicit redaction notes.

Unsafe payloads must stay omitted or summarized before ingestion.

## Current Gaps

- The current dashboard view is intentionally compact; deeper run drill-in is still a future dashboard productization task.
- Browser-based visual QA may be unavailable in some Codex sessions. When that happens, use focused React tests, `web build` and local HTTP smoke checks as fallback evidence.

## Validated Smoke Flow

Start the server:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
```

Send and verify local self-observation events:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-observation.ps1 `
  -ApiBase http://127.0.0.1:8787
```

Optional failure path:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-observation.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -IncludeFailure
```

Expected result:

- `/v1/runs/:runId` returns the smoke run summary and redacted events.
- `/v1/events?run_id=<runId>` returns only the smoke events for that run.
- `/v1/notifications` includes a skipped placeholder when ntfy is not configured.
- The dashboard self-observation panel counts Codex, runner, smoke and notification events.
