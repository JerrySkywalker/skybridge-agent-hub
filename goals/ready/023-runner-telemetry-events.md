# Goal 023: Runner Telemetry Events

## Background

Runner execution currently writes local `.agent/runs` logs. SkyBridge should also ingest runner lifecycle events through `skybridge.agent_event.v1` so the dashboard can show autonomous development progress.

## Tasks

- Define normalized event payloads for runner lifecycle states.
- Emit `agent.*`, `run.*`, `tool.*`, `notification.*` or related event families from `yolo-runner.ps1`.
- Send events to the local SkyBridge server when configured.
- Keep command output and repair logs redacted or summarized by default.
- Document the event configuration.

## Completion Criteria

- Runner start, claim, Codex invocation, check result, repair attempt, completion and failure can appear in the SkyBridge event stream.
- The runner still works when the SkyBridge server is offline.
- No full command output, secrets or tokens are uploaded by default.
- `just check` or `corepack pnpm check` passes.

## Prohibited Changes

- Do not send full stdout/stderr by default.
- Do not require a running server for local runner operation.
- Do not implement remote control.
