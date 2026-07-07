# SkyBridge MVP Codex Local Diff Demo

## What MG372D Proves

MG372D extends the MVP demo spine from local task lifecycle and
controller-created draft PR proof into a Codex-generated local diff proof.

It proves this flow:

```text
local safe demo spine -> one Codex call -> isolated copied workspace ->
docs-only file change -> changed-file capture -> diff.patch -> review summary
```

The demo calls Codex once and asks it to create exactly one docs-only artifact:

```text
docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
```

## Why This Is Local Diff Only

MG372D intentionally stops before GitHub mutation. The purpose is to prove
that SkyBridge can ask Codex for a small, reviewable local diff and capture
safe evidence before any branch, push or PR creation is introduced.

The implementation uses an isolated archive-copied workspace under:

```text
.agent/tmp/skybridge-mvp-codex-diff/workspace/
```

The copied workspace is not a Git repository, so the demo cannot commit or push
from that workspace. The main worktree remains clean after a successful run.

## Why It Does Not Create PR

MG372B already proved a controller-created draft PR demo. MG372D proves the
missing Codex-generated diff step separately so failures can be diagnosed
before PR creation is reintroduced.

The demo records:

- `pr_created=false`
- `branch_pushed=false`
- `commit_created=false`
- `demo_pr_311_modified=false`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `token_printed=false`

## Preview

Preview mode writes policy and report artifacts but does not call Codex:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff-preview `
  -Json
```

Expected preview fields:

- `would_call_codex=true`
- `codex_called=false`
- `would_create_isolated_workspace=true`
- `would_generate_diff=true`
- `pr_created=false`
- `branch_pushed=false`
- `token_printed=false`

## Apply

After the MG372D implementation PR is merged and `main` is synced, run the
authorized apply command exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372D_CALL_CODEX_ONCE_FOR_LOCAL_DOCS_ONLY_DIFF_DEMO `
  -Json
```

The apply command requires:

- clean `main`
- `main` synced with `origin/main`
- MG372C baseline contained in `HEAD`
- Git available
- Codex CLI available
- exact confirmation text
- no existing MG372D workspace
- docs-only allowlist pass

## Artifacts

Artifacts are written under:

```text
.agent/tmp/skybridge-mvp-codex-diff/
```

Important files:

- `codex-local-diff-report.json`
- `codex-local-diff-report.md`
- `codex-local-diff-prompt.md`
- `codex-local-diff-last-message.md`
- `codex-local-diff-changed-files.json`
- `codex-local-diff-allowlist-check.json`
- `codex-local-diff-review-summary.md`
- `codex-local-diff.patch`
- `codex-local-diff-safety.json`
- `codex-local-diff-artifact-index.json`

The JSON report schema is:

```text
skybridge.mvp_demo.codex_local_diff.v1
```

## Inspect The Diff

After apply, inspect:

```text
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff.patch
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff-review-summary.md
.agent/tmp/skybridge-mvp-codex-diff/workspace/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
```

The patch is local evidence only. It is not committed, pushed or attached to a
PR by MG372D.

## What It Does Not Prove

- It does not create a GitHub PR.
- It does not push a branch.
- It does not commit to `main`.
- It does not prove repeated Codex-generated diffs.
- It does not prove Codex-generated draft PR creation.
- It does not resume MG371B or TUI-created PR work.
- It does not start a worker loop, queue runner or run-forever process.
- It does not call live Hermes or MCP.
- It does not enable auto-merge.
- It does not create release, tag or asset uploads.

## Safety Boundaries

MG372D keeps:

- `worker_loop_started=false`
- `queue_runner_started=false`
- `run_forever_started=false`
- `hermes_live_called=false`
- `mcp_run_called=false`
- `auto_merge_enabled=false`
- `release_created=false`
- `tag_created=false`
- `asset_uploaded=false`
- `raw_output_exported=false`
- `token_printed=false`

Raw Codex process logs, if produced by the local CLI, remain local-only under
the artifact directory and are not included in the JSON or Markdown report.

## Next Step Recommendation

If MG372D passes, the next milestone should be:

```text
MG372E2 Codex-generated Draft PR Demo
```

MG372E2 should take the validated local docs-only diff and create one
controller-created draft PR. It should still not use TUI-created PR behavior.
