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

MG372D1 implementation merged, but the post-merge rerun blocked because Codex
timed out and did not produce the target artifact. The collector was no
longer the primary blocker: the worktree was clean before Codex, the
Git-index collector was active and the main worktree remained clean.

MG372D2 makes that execution failure diagnosable and easier to avoid. It adds
a Codex doctor, explicit timeout seconds, local-only stdout/stderr log paths,
execution diagnostics, failure classification, mock success/timeout/disallowed
file smokes and a shorter deterministic prompt. It still requires a
Codex-created target artifact and a non-empty Git-generated patch before the
demo can pass.

MG372D2 implementation merged, but its post-merge rerun blocked before Codex
was called because a stale registered local worktree already existed at:

```text
.agent/tmp/skybridge-mvp-codex-diff/worktree/
```

The Codex CLI was available and its version was detected, so the active blocker
became stale local worktree cleanup, not Codex availability. MG372D2R adds an
explicit cleanup gate that can remove only that stale `.agent/tmp` worktree
after the exact authorization phrase is provided, records before/after
worktree lists and then reruns the normal Codex local-diff apply flow once.

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
- `would_run_codex_doctor=true`
- `would_clean_existing_worktree=true` when a stale worktree is present
- `cleanup_requested=false`
- `pr_created=false`
- `branch_pushed=false`
- `token_printed=false`

## Apply

After the MG372D2R cleanup-gate implementation PR is merged and `main` is
synced, run the authorized cleanup and apply command exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-local-diff `
  -UseTempDatabase `
  -Apply `
  -CleanExistingCodexWorktree `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372D2R_CLEAN_STALE_CODEX_DIFF_WORKTREE_AND_RERUN_CODEX_ONCE `
  -CodexTimeoutSeconds 900 `
  -Json
```

The apply command requires:

- clean `main`
- `main` synced with `origin/main`
- MG372D baseline contained in `HEAD`
- Git available
- Codex CLI available
- exact confirmation text
- no existing MG372D2R worktree, or explicit cleanup of the stale registered
  `.agent/tmp/skybridge-mvp-codex-diff/worktree` path
- docs-only allowlist pass

MG372D2R pass criteria:

- stale worktree cleaned or verified absent
- `cleanup_requested=true`
- `cleanup_completed=true` when the stale worktree is present
- changed files exactly equal
  `docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md`
- `codex_available=true`
- `codex_called=true`
- `codex_call_count=1`
- `docs_only_allowlist_passed=true`
- `diff.patch` exists, is non-empty and mentions the artifact path
- `workspace_clean_before_codex=true`
- `git_index_collector_used=true`
- `hash_comparison_used=false`
- `target_artifact_exists=true`
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
- `codex-local-diff-stdout.log`
- `codex-local-diff-stderr.log`
- `codex-local-diff-last-message.md`
- `codex-local-diff-changed-files.json`
- `codex-local-diff-allowlist-check.json`
- `codex-local-diff-review-summary.md`
- `codex-local-diff.patch`
- `codex-local-diff-safety.json`
- `codex-local-diff-collector-diagnostics.json`
- `codex-local-diff-execution-diagnostics.json`
- `codex-local-diff-failure-classification.json`
- `codex-local-diff-cleanup-report.json`
- `codex-local-diff-cleanup-report.md`
- `codex-local-diff-worktree-list-before.txt`
- `codex-local-diff-worktree-list-after.txt`
- `codex-local-diff-cleanup-safety.json`
- `codex-local-diff-artifact-index.json`

The JSON report schema is:

```text
skybridge.mvp_demo.codex_local_diff.v4
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

Demo PR #311 remains untouched by MG372D2R.

If MG372D2R passes, the next milestone should be:

```text
MG372E2 Codex-generated Draft PR Demo
```

MG372E2 should take the validated local docs-only diff and create one
controller-created draft PR. It should still not use TUI-created PR behavior.
