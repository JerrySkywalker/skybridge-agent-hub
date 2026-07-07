# SkyBridge MVP Codex Local Diff Demo

## What MG372D Proves

MG372D extends the MVP demo spine from local task lifecycle and
controller-created draft PR proof into a Codex-generated local diff proof.

It proves this flow:

```text
local safe demo spine -> one Codex call -> isolated Git worktree ->
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

MG372D implementation merged, but the first post-merge demo run blocked. The
copied/archive workspace collector drifted from Git blob/index semantics on
Windows, reported unrelated line-ending/hash differences as changed files and
wrote an empty `diff.patch`.

MG372D1 fixes the collector. The implementation now uses an isolated detached
Git worktree under:

```text
.agent/tmp/skybridge-mvp-codex-diff/worktree/
```

The collector uses `git status --porcelain=v1`, Git diff name-only output and
a Git-generated patch. It does not compare raw file hashes against the Windows
working tree. The demo still does not push or commit; `commit_created=false`
means the isolated worktree HEAD remains at the baseline commit.

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
- `workspace_setup_method=git_worktree`
- `would_use_git_index_collector=true`
- `would_generate_non_empty_patch=true`
- `pr_created=false`
- `branch_pushed=false`
- `token_printed=false`

## Apply

After the MG372D1 collector-fix implementation PR is merged and `main` is
synced, run the authorized apply command exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372D1_RERUN_CODEX_ONCE_FOR_LOCAL_DOCS_ONLY_DIFF_DEMO `
  -Json
```

The apply command requires:

- clean `main`
- `main` synced with `origin/main`
- MG372D baseline contained in `HEAD`
- Git available
- Codex CLI available
- exact confirmation text
- no existing MG372D1 worktree
- docs-only allowlist pass

MG372D1 pass criteria:

- changed files exactly equal
  `docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md`
- `docs_only_allowlist_passed=true`
- `diff.patch` exists, is non-empty and mentions the artifact path
- `workspace_clean_before_codex=true`
- `git_index_collector_used=true`
- `hash_comparison_used=false`
- `main_worktree_clean_after=true`
- `pr_created=false`
- `branch_pushed=false`
- `commit_created=false`
- `demo_pr_311_modified=false`
- `token_printed=false`

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
- `codex-local-diff-collector-diagnostics.json`
- `codex-local-diff-artifact-index.json`

The JSON report schema is:

```text
skybridge.mvp_demo.codex_local_diff.v2
```

## Inspect The Diff

After apply, inspect:

```text
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff.patch
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff-review-summary.md
.agent/tmp/skybridge-mvp-codex-diff/worktree/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
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

If MG372D1 passes, the next milestone should be:

```text
MG372E2 Codex-generated Draft PR Demo
```

MG372E2 should take the validated local docs-only diff and create one
controller-created draft PR. It should still not use TUI-created PR behavior.
