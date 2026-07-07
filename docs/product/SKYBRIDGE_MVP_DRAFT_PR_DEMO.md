# SkyBridge MVP Draft PR Demo

## What MG372B Proves

MG372B extends the local-safe MVP demo with the next user-facing slice:

```text
local safe task lifecycle -> controller-created docs branch ->
controller-created draft PR -> PR evidence artifacts -> operator inspection
```

The demo proves SkyBridge can coordinate one safe task, then use the controller
path to create exactly one deterministic docs-only branch and one draft PR.

## Controller-Created, Not TUI-Created

The demo is intentionally controller-created. MG371B / TUI-created PR work is
frozen. MG372B does not invoke the TUI PR provider, does not enable TUI-created
branches or PRs, and does not implement TUI PR execution mode.

## Preview

Preview mode writes policy artifacts only. It must not create branches or PRs:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode controller-draft-pr-preview `
  -Json
```

Preview reports:

- `would_create_branch=true`
- `would_create_draft_pr=true`
- `branch_policy_passed=true`
- `docs_only_allowlist_passed=true`
- `controller_created_branch=false`
- `controller_created_draft_pr=false`
- `pr_created=false`
- `token_printed=false`

## Apply

Apply mode is authorized only with the exact MG372B confirmation text:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode controller-draft-pr `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372B_CREATE_ONE_CONTROLLER_CREATED_DOCS_ONLY_DRAFT_PR_DEMO `
  -Json
```

Apply mode requires a clean, synced `main`, Git, GitHub CLI, GitHub
authentication, the branch policy, the docs-only allowlist and one-branch /
one-draft-PR policy before mutation.

## Branch And PR

The demo branch uses:

```text
demo/mg372b-controller-draft-pr-<utc-date>-<short-id>
```

The demo PR title starts with:

```text
MG372B Demo: Controller-created Draft PR
```

The demo PR changes only:

```text
docs/product/MG372B_CONTROLLER_DRAFT_PR_DEMO_ARTIFACT.md
```

## Why The Demo PR Remains Draft And Open

The demo PR is the inspection target. The script must not mark it ready, merge
it, close it or enable auto-merge. Jerry should be able to inspect the branch,
the PR body, the changed file and the local artifacts after the demo command
finishes.

## Artifacts

Artifacts are written under:

```text
.agent/tmp/skybridge-mvp-demo-pr/
```

Required files:

- `mvp-pr-demo-report.json`
- `mvp-pr-demo-report.md`
- `mvp-pr-demo-state.json`
- `mvp-pr-demo-task.json`
- `mvp-pr-demo-worker.json`
- `mvp-pr-demo-preflight.json`
- `mvp-pr-demo-branch-plan.json`
- `mvp-pr-demo-allowlist-check.json`
- `mvp-pr-demo-pr-metadata.json`
- `mvp-pr-demo-provider-report.json`
- `mvp-pr-demo-safety.json`
- `mvp-pr-demo-artifact-index.json`

The JSON report uses schema:

```text
skybridge.mvp_demo.controller_draft_pr.v1
```

## What It Does Not Prove

- It does not call Codex.
- It does not generate code or diffs with an agent.
- It does not use TUI-created PR behavior.
- It does not authorize repeated demo PRs.
- It does not authorize non-docs changes.
- It does not mark the demo PR ready or merge it.
- It does not start worker loops, queue runners or run-forever behavior.
- It does not call live Hermes or MCP.
- It does not deploy, release, tag or upload assets.

## Safety Boundaries

The demo preserves:

- `codex_called=false`
- `tui_created_branch=false`
- `tui_created_pr=false`
- `worker_loop_started=false`
- `queue_runner_started=false`
- `run_forever_started=false`
- `hermes_live_called=false`
- `mcp_run_called=false`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `raw_input_persisted=false`
- `token_printed=false`

## Next Step Recommendation

Recommended next milestone:

```text
MG372D Codex-generated Local Diff Demo
```

MG372C reviewed the MVP demo line and recommends continuing in this repository
while keeping MG371B / TUI-created PR work frozen. MG372D should add one
Codex-generated docs-only local diff demo and stop before PR creation.
