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
        +-- GET /v1/runs
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

- Server run summaries only expose the aggregate list; a specific run view and scoped event query are needed for dashboard drill-in and smoke assertions.
- Runner and smoke events should produce stable, useful run/session grouping without requiring any schema-breaking change.
- Dashboard widgets need a self-observation view that distinguishes Codex, runner, manual smoke and failure-trigger events.
- A local script should prove the loop without requiring secrets or external services.
