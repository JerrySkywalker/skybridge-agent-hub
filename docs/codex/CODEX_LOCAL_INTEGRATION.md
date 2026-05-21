# Codex Local Integration

SkyBridge treats local Codex telemetry as a first-party production path, not as an ad hoc dashboard feed. Codex TUI hooks, `codex exec --json` streams and PowerShell helper scripts must normalize source payloads into `skybridge.agent_event.v1`, redact unsafe data before delivery, fail open when the server is unavailable and leave enough local evidence for replay and troubleshooting.

## Supported Event Families

Codex adapters may emit these normalized event families:

```text
session.*
run.*
turn.*
tool.*
approval.*
file.*
diff.*
message.*
agent.*
notification.*
```

Current Codex hook mappings:

| Codex hook | SkyBridge event | Notes |
| --- | --- | --- |
| `SessionStart` startup | `session.started` | Starts a local Codex session. |
| `SessionStart` resume | `session.started` | Payload includes the safe startup/resume marker when present. |
| `UserPromptSubmit` | `run.started` | Starts or resumes a run group using `run_id`, `conversation_id` or `session_id`. |
| `PreToolUse` Bash | `tool.started` | Sends command presence, length and redacted command summary only. |
| `PostToolUse` Bash success | `tool.completed` | Sends exit status and bounded output metadata only. |
| `PostToolUse` Bash failure | `tool.failed` | Uses warning/error severity and omits full stdout/stderr. |
| `PreToolUse` apply_patch | `tool.started` plus optional `file.edited`/`diff.updated` | File/diff events are emitted only from safe path/diff summaries. |
| `PermissionRequest` | `approval.requested` | Notification-triggering warning event. |
| `Stop` | `turn.completed` | Marks a Codex turn boundary. |
| Unknown/minimal payload | `agent.idle` | Preserves adapter liveness without trusting unknown payload content. |

`codex exec --json` maps result and error records to `run.completed`, `run.failed` and `message.completed` while omitting free-form summaries by default.

## Local Delivery Design

1. Codex invokes `scripts/powershell/codex-dashboard-hook.ps1` with hook JSON on stdin.
2. The script performs lightweight normalization into `skybridge.agent_event.v1`.
3. The normalized event is written to a bounded local JSONL spool before network delivery.
4. The script posts to `SKYBRIDGE_API_BASE/v1/events`, defaulting to `http://127.0.0.1:8787`.
5. Delivery failures never fail the Codex hook. Events remain in the local spool for replay.
6. `scripts/powershell/replay-codex-hook-spool.ps1` resends queued events and archives successfully delivered lines.
7. Server APIs persist accepted events, expose Codex-specific filters and derive run summaries from already-redacted payloads.
8. The dashboard surfaces recent Codex runs, latest hook event and local spool status when status events are available.

The spool is local operator data. It must live under a gitignored local directory such as `.agent/codex-hook-spool` or `%USERPROFILE%\.codex\skybridge\spool`, and it must contain normalized, redacted events rather than raw hook stdin.

## Redaction Decisions

Codex hook payloads can contain secrets, command output, prompts, file paths and tool inputs. SkyBridge uses these defaults:

- Do not upload full commands, stdout, stderr, prompts or Codex JSONL records.
- Replace secret-like values, bearer tokens, authorization headers, API keys and password-like fields with `[REDACTED]`.
- Keep command metadata limited to presence, length and a short redacted prefix.
- Keep tool output metadata limited to presence, length, line count, exit status and a short redacted prefix.
- Bound unknown nested values by depth, key count and string length.
- Prefer relative or redacted paths where possible; never treat a path as a secret-free payload by itself.

## Server and UI Requirements

`POST /v1/events` accepts only normalized `skybridge.agent_event.v1` events and returns clean 400 validation errors for invalid payloads. Codex operator queries should support:

- `source_platform=codex`
- `source_adapter=codex-hook` or `codex-exec-json`
- `run_id`
- `session_id`
- `type`
- `from` and `to` ISO timestamps
- bounded `limit`

Run summaries should expose safe Codex metadata: branch, cwd, goal, tool counts, failed tool counts and latest safe message summary when present.

## Mega Goal 002 Status

Completed:

- Hook adapter fixtures and malformed payload tests.
- Redaction semantics in TypeScript adapters and PowerShell hook scripts.
- Installer, restore, hook event tester and replay scripts.
- Smoke coverage for online delivery and offline spool replay.
- Dashboard Codex operator view without remote-control behavior.

Remaining follow-up:

- Share redaction logic from one source package rather than maintaining TypeScript and PowerShell implementations separately.
