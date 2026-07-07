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

MG372A local-safe mode proves:

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

MG372B controller draft PR mode proves the next slice after the implementation
PR is merged:

- A controller path can run the same safe local task spine.
- The controller can create exactly one deterministic docs-only branch.
- The controller can create exactly one docs-only draft PR.
- The draft PR remains open, draft-only, unmerged and ready for operator
  inspection.
- The demo still records `codex_called=false`, `tui_created_branch=false`,
  `tui_created_pr=false`, `auto_merge_enabled=false` and
  `token_printed=false`.

MG372D Codex local diff mode added the next slice after the implementation PR
merged, but the first post-merge demo run blocked. MG372D1 fixed the
collector, then its rerun blocked because Codex timed out and produced no
target artifact. MG372D2 keeps the fixed collector and hardens execution:

- The MVP spine can call Codex exactly once under exact confirmation.
- Codex writes into an isolated Git worktree, not the main worktree.
- Changed files are captured with Git-index semantics, not raw file-hash
  comparison against the Windows checkout.
- The Codex doctor records availability/version diagnostics before execution.
- Timeout and no-artifact cases are classified explicitly.
- Mock success, timeout and disallowed-file smokes exercise the production
  collector without running real Codex in CI.
- `codex-local-diff.patch` must be non-empty and a review summary is produced.
- The demo stops before commit, push or PR creation.
- The safety boundary records `pr_created=false`, `branch_pushed=false`,
  `commit_created=false`, `demo_pr_311_modified=false` and
  `token_printed=false`.

## What It Does Not Prove

- MG372A local-safe mode and MG372B controller draft PR mode do not call Codex.
- MG372D calls Codex once, but only for a local docs-only diff.
- MG372A local-safe mode does not create a GitHub branch or PR.
- MG372B controller draft PR mode creates only one controller-created docs-only
  draft PR under exact confirmation.
- MG372D does not create a GitHub branch or PR.
- It does not use TUI-created PR behavior.
- It does not start a worker loop, queue runner or run-forever process.
- It does not call live Hermes or MCP.
- It does not touch production infrastructure.
- It does not enable auto-merge, release, tag or asset upload.

## Controller Draft PR Demo

Preview policy and artifacts without branch or PR mutation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode controller-draft-pr-preview `
  -Json
```

After MG372B is merged, run the authorized apply command exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode controller-draft-pr `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372B_CREATE_ONE_CONTROLLER_CREATED_DOCS_ONLY_DRAFT_PR_DEMO `
  -Json
```

The apply command creates one branch matching
`demo/mg372b-controller-draft-pr-<utc-date>-<short-id>` and one draft PR whose
title starts with `MG372B Demo: Controller-created Draft PR`. The demo PR
changes only `docs/product/MG372B_CONTROLLER_DRAFT_PR_DEMO_ARTIFACT.md` and
must remain draft/open for inspection.

See [SKYBRIDGE_MVP_DRAFT_PR_DEMO.md](SKYBRIDGE_MVP_DRAFT_PR_DEMO.md).

## Review Gate

MG372C reviews the MG372A/MG372B MVP demo line and recommends continuing in
this repository. The review keeps MG371B / TUI-created PR work frozen and
selects MG372D Codex-generated Local Diff Demo as the next step.

See [SKYBRIDGE_MVP_DEMO_REVIEW.md](SKYBRIDGE_MVP_DEMO_REVIEW.md).

## Codex Local Diff Demo

Preview policy and artifacts without calling Codex:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff-preview `
  -Json
```

After MG372D2 is merged, run the authorized apply command exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372D2_RERUN_CODEX_ONCE_FOR_LOCAL_ARTIFACT_PRODUCTION_DEMO `
  -CodexTimeoutSeconds 900 `
  -Json
```

The apply command calls Codex once in an isolated Git worktree, allows only
`docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md`, writes
non-empty `codex-local-diff.patch` and stops before commit, push or PR
creation. MG372D1 also writes `codex-local-diff-collector-diagnostics.json`.
MG372D2 additionally writes `codex-local-diff-execution-diagnostics.json` and
`codex-local-diff-failure-classification.json`.

See [SKYBRIDGE_MVP_CODEX_LOCAL_DIFF_DEMO.md](SKYBRIDGE_MVP_CODEX_LOCAL_DIFF_DEMO.md).

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
- Codex-generated local docs-only diff demo.
- Still no TUI-created PR behavior.
- Still no unbounded worker loop.
- Still no auto-merge, release, tag or asset upload.

## Next Step

Recommended next milestone after MG372D2 passes:

```text
MG372E2 Codex-generated Draft PR Demo
```

MG371B and TUI-created PR execution mode remain frozen for now. MG372E2 should
take the validated local docs-only diff and create a controller-created draft
PR, still not TUI-created.

`token_printed=false`
