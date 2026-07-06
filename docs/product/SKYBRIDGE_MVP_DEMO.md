# SkyBridge MVP Demo

## Why This Exists

MG372A adds the first short product-verifiable demo spine for SkyBridge. The
repository already has many safety gates, worker APIs and orchestration
milestones, but a new operator needs one local command that proves the task
lifecycle is usable end to end.

The MVP demo focuses on the smallest safe slice:

```text
one command -> isolated local server/database -> demo project/goal/task ->
demo worker registration -> one claim/start/complete lifecycle -> reports
```

## One-Command Local Demo

Run from the repository root:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode local-safe `
  -UseTempDatabase `
  -Json
```

`-UseTempDatabase` starts a bounded local SkyBridge server with an isolated
SQLite file, waits for `/v1/health`, runs one local-safe task lifecycle, writes
reports, and stops the child server process.

## What The Demo Proves

- A local SkyBridge server can be started with an isolated demo database.
- The server can create the demo project `skybridge-mvp-demo`.
- The server can create the demo goal `mg372a-local-safe-demo`.
- The server can create the demo task `mg372a-local-safe-task-001`.
- A local demo worker can register and heartbeat.
- Exactly one task can be claimed, started and completed with PollOnce
  semantics.
- The lifecycle writes human-readable and machine-readable evidence.
- The safe boundary remains explicit:
  `codex_called=false`, `pr_created=false`, `branch_created=false`,
  `worker_loop_started=false`, `run_forever_started=false` and
  `token_printed=false`.

## What It Does Not Prove

- It does not call Codex.
- It does not create a GitHub branch or PR.
- It does not use TUI-created PR behavior.
- It does not start a worker loop, queue runner or run-forever process.
- It does not call live Hermes or MCP.
- It does not touch production infrastructure.
- It does not enable auto-merge, release, tag or asset upload.

## Artifacts

Artifacts are written under:

```text
.agent/tmp/skybridge-mvp-demo/
```

Required files:

- `mvp-demo-report.json`
- `mvp-demo-report.md`
- `mvp-demo-state.json`
- `mvp-demo-events.json`
- `mvp-demo-task.json`
- `mvp-demo-worker.json`
- `mvp-demo-safety.json`
- `mvp-demo-command-transcript.txt`
- `mvp-demo-artifact-index.json`

The JSON report uses schema:

```text
skybridge.mvp_demo.local_safe.v1
```

## Inspect Status

Show the last demo result:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode status `
  -Json
```

Show the Markdown report path and summary:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode report `
  -Json
```

Open the Markdown report explicitly:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode report `
  -OpenReport
```

## Phase Mapping

Phase 1:

- Local task lifecycle demo.
- Isolated local SQLite database.
- One demo worker.
- One safe task.
- Sanitized reports only.

Phase 2:

- Controller-created draft PR demo.
- Still no TUI-created PR behavior.
- Still no unbounded worker loop.
- Still no auto-merge, release, tag or asset upload.

## Next Step

Recommended next milestone:

```text
MG372B Controller-created Draft PR Demo
```

MG371B and TUI-created PR execution mode are frozen for now. The next product
slice should demonstrate a controller-created draft PR from the MVP spine, not
a TUI-created PR.

`token_printed=false`
