# SkyBridge MVP Demo Review

## Executive Summary

The MG372 MVP demo line passed.

MG372A proved a one-command local-safe task lifecycle. MG372B proved the next
slice: a controller-created docs-only branch and draft PR with PR evidence
recorded, while leaving the demo PR draft/open for human review.

Decision: continue in the current repository. Do not rewrite from scratch. Do
not resume MG371B / TUI-created PR work now. The next milestone should be
MG372D Codex-generated Local Diff Demo.

## Evidence Reviewed

MG372A local-safe command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode local-safe `
  -UseTempDatabase `
  -Json
```

MG372A result summary:

- `demo_result=pass`
- `task_created=true`
- `worker_registered=true`
- `task_claimed=true`
- `task_completed=true`
- `fixture_mode=false`
- `real_worker_execution=true`
- `codex_called=false`
- `pr_created=false`
- `branch_created=false`
- `worker_loop_started=false`
- `queue_runner_started=false`
- `run_forever_started=false`
- `token_printed=false`

MG372B controller-created draft PR demo command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-mvp-demo.ps1 `
  -Mode controller-draft-pr `
  -UseTempDatabase `
  -Apply `
  -ConfirmationText I_UNDERSTAND_AUTHORIZE_MG372B_CREATE_ONE_CONTROLLER_CREATED_DOCS_ONLY_DRAFT_PR_DEMO `
  -Json
```

MG372B result summary:

- `demo_result=pass`
- `task_created=true`
- `worker_registered=true`
- `task_claimed=true`
- `task_completed=true`
- `fixture_mode=false`
- `real_worker_execution=true`
- `server_task_pr_evidence_recorded=true`
- `controller_created_branch=true`
- `controller_created_draft_pr=true`
- `demo_pr_left_open=true`
- `demo_pr_marked_ready=false`
- `demo_pr_merged=false`
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

Implementation PR:

- PR #310: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/310`
- Merge commit: `a971f555f31db86869b10261be3c04b3d3d1317e`

Demo PR:

- PR #311: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/311`
- Branch: `demo/mg372b-controller-draft-pr-20260706-a971f55`
- Commit: `222ca088cbf25a4037cdf64fe598c141de274f2c`
- Changed file: `docs/product/MG372B_CONTROLLER_DRAFT_PR_DEMO_ARTIFACT.md`
- State: draft/open for human review

Artifact directories:

- `.agent/tmp/skybridge-mvp-demo/`
- `.agent/tmp/skybridge-mvp-demo-pr/`
- `.agent/tmp/skybridge-mvp-demo-review/`

## What Is Now Proven

- One-command local-safe lifecycle works.
- Server task lifecycle is usable.
- Worker registration works.
- Task claim/start/complete path works.
- Artifacts are produced.
- Controller-created docs-only branch works.
- Controller-created draft PR works.
- PR evidence can be recorded.
- Demo PR can remain draft/open for human review.

## What Is Not Proven

- Codex-generated code or docs changes are not yet proven in this MVP line.
- Isolated worktree diff generation is not yet proven in this MVP line.
- Repeated controller-created PR runs are not yet proven.
- TUI-created PR is not part of the MVP and remains frozen.
- Always-on worker loop remains frozen.
- Remote execution remains out of scope.
- Auto-merge remains out of scope.
- Release/tag/assets remain out of scope.

## Why Earlier Development Felt Slow

Earlier work spent a lot of effort on safety gates, TUI-created PR capability,
manual operation evidence and future execution boundaries. That work was
valuable, but it did not quickly show a user-visible SkyBridge product slice.

MG372A and MG372B corrected the direction by making the task lifecycle visible:
first as a one-command local task lifecycle, then as a controller-created
docs-only draft PR that an operator can inspect.

## Decision

Primary recommendation: Option A, continue the current repository and add a
Codex-generated diff demo next.

Continue current repository. Do not rewrite from scratch. Freeze MG371B /
TUI-created PR work. The next milestone should be:

```text
MG372D Codex-generated Local Diff Demo
```

Reason: the current repo now has enough reusable infrastructure. A rewrite is
not justified unless the next Codex diff demo fails.

## Cut / Freeze List

Freeze for now:

- MG371B TUI-created PR
- worker loop / run forever
- auto-merge
- Hermes live
- MCP
- remote execution
- multi-agent orchestration
- release/tag/assets
- dashboard polish beyond showing MVP status

## Next Milestone Proposal

Milestone:

```text
MG372D Codex-generated Local Diff Demo
```

Purpose:

- use the existing MVP demo spine
- call Codex once
- generate a docs-only local diff in an isolated workspace or temporary branch
- do not create a PR yet
- produce `diff.patch` and a review summary
- keep controller-created PR as a later MG372E2 or MG373A step

Do not skip directly to repeated PR creation.

MG372D implements this proposal as a local-diff-only demo. It adds
`codex-local-diff-preview` for CI-safe policy checks and an exact-confirmed
`codex-local-diff` apply mode that calls Codex once and stops before commit,
push or PR creation. The first MG372D demo run blocked because the
archive-copied workspace collector drifted from Git blob/index semantics and
reported unrelated line-ending/hash differences.

MG372D1 fixes that collector blocker by using a detached Git worktree,
Git-index-based changed-file collection, collector diagnostics and a
non-empty patch requirement. Its post-merge rerun then blocked on the next
problem: Codex timed out and did not create the target artifact.

MG372D2 adds Codex doctor checks, explicit timeout diagnostics, failure
classification, mock success/timeout/disallowed-file smokes and a shorter
deterministic prompt. MG372D2 implementation merged, but its post-merge rerun
blocked before Codex because the previous Codex local-diff worktree was still
registered. MG372D2R adds an explicit stale-worktree cleanup gate and rerun
authorization. If MG372D2R passes, the next milestone should be:

```text
MG372E2 Codex-generated Draft PR Demo
```

MG372E2 should remain controller-created, not TUI-created, and should not
proceed to repeated PR creation.

## Demo PR #311 Handling

Recommendation:

- leave PR #311 draft/open until Jerry manually reviews it
- do not merge it automatically
- do not close it automatically
- if Jerry approves it later, use a separate explicit authorization goal to
  mark ready and merge or close it

## Safety Record

- `codex_called=false` for MG372B
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
