# SkyBridge MVP Codex-generated Draft PR Demo

## What MG372E2 Proves

MG372E2 joins the two proven MVP slices:

```text
task lifecycle -> Codex-generated local docs diff -> controller-created branch ->
controller-created commit -> controller-created draft PR -> human review hold
```

It creates one controller-owned draft PR from the already validated MG372D2R
Codex local diff artifact:

```text
docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
```

## Why It Uses MG372D2R

MG372D2R already proved that Codex was called exactly once, exited `0`, changed
only the allowed docs artifact, produced a non-empty Git patch and stopped
before commit, push or PR creation. MG372E2 treats that retained artifact set
as the source of truth instead of asking Codex to regenerate it.

Source artifacts:

```text
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff-report.json
.agent/tmp/skybridge-mvp-codex-diff/codex-local-diff.patch
.agent/tmp/skybridge-mvp-codex-diff/worktree/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
```

## Why It Does Not Call Codex Again

The point of MG372E2 is packaging and PR creation, not generation quality.
Calling Codex again would blur whether the demo failed in generation, diff
collection or GitHub packaging. MG372E2 records:

- `codex_called_in_mg372e2=false`
- `source_codex_called=true`
- `source_codex_call_count=1`
- `source_diff_patch_non_empty=true`

## Why The Demo PR Stays Draft

The demo PR is an inspection artifact. It must remain draft/open for Jerry
review and must not be marked ready, merged, closed or auto-merged by the demo.

## Preview

Preview validates policy and source artifacts without branch, commit, push or
PR mutation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-diff-draft-pr `
  -Json
```

Equivalent explicit preview mode:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-diff-draft-pr-preview `
  -Json
```

## Apply

After the MG372E2 implementation PR is merged and `main` is fast-forwarded,
run exactly once:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode codex-diff-draft-pr `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372E2_CREATE_ONE_CODEX_GENERATED_DOCS_ONLY_DRAFT_PR_DEMO `
  -Json
```

The apply command requires clean synced `main`, Git, GitHub CLI auth, draft/open
PR #311, passing source artifact validation and no existing MG372E2 demo branch
or PR.

## Created Branch And PR

The demo branch uses:

```text
demo/mg372e2-codex-draft-pr-<utc-date>-<short-id>
```

The draft PR title starts with:

```text
MG372E2 Demo: Codex-generated Draft PR
```

The demo PR may change only:

```text
docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md
```

## Artifacts

Artifacts are written under:

```text
.agent/tmp/skybridge-mvp-codex-draft-pr/
```

Important files:

- `codex-draft-pr-report.json`
- `codex-draft-pr-report.md`
- `codex-draft-pr-state.json`
- `codex-draft-pr-task.json`
- `codex-draft-pr-worker.json`
- `codex-draft-pr-preflight.json`
- `codex-draft-pr-source-diff-validation.json`
- `codex-draft-pr-branch-plan.json`
- `codex-draft-pr-allowlist-check.json`
- `codex-draft-pr-pr-metadata.json`
- `codex-draft-pr-provider-report.json`
- `codex-draft-pr-safety.json`
- `codex-draft-pr-artifact-index.json`

The JSON report schema is:

```text
skybridge.mvp_demo.codex_generated_draft_pr.v1
```

## What It Does Not Prove

- It does not prove repeated Codex-generated PR creation.
- It does not call Codex in MG372E2.
- It does not create a TUI-created branch or PR.
- It does not start a worker loop, queue runner or run-forever process.
- It does not call live Hermes or MCP.
- It does not enable auto-merge.
- It does not create a release, tag or asset upload.
- It does not merge or close the demo PR.

## Safety Boundaries

MG372E2 keeps:

- `codex_called_in_mg372e2=false`
- `demo_pr_311_modified=false`
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
- `raw_output_exported=false`
- `token_printed=false`

## Next Step Recommendation

After the demo draft PR exists and remains open for review, the next milestone
should be:

```text
MG372F MVP End-to-End Review Gate
```

MG372F should review the full MVP chain and decide whether to keep building in
this repository, add dashboard UX for the MVP chain, add repeated controlled
Codex PR generation or cut complexity before expanding.
