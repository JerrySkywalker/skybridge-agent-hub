# Failed Task Pattern Analysis

This note captures recurring failure modes observed in four SkyBridge dogfood
tasks so future operators can recover them without re-investigating the same
history.

Analyzed tasks:

| Task | Outcome pattern | Safe source summary |
| --- | --- | --- |
| `task_proposal-4212a5e1447212c0` | Child PR #73 merged after checks passed, but the task was marked failed while checks were pending. Evidence repair later recorded `recovered=true`, `ci_status=passed_after_pending`, and `risk_status=low_docs_only`. | `docs/dev/PROGRESS.md`, `docs/dev/HERMES_ASSISTED_SELF_BOOTSTRAP_SPRINT.md` |
| `task_proposal-d90d09da925d2cf0` | First run failed on Codex transport EOF before child PR packaging. Targeted retry succeeded, PR #69 merged, and evidence repair preserved raw `failed` history while marking the task recovered. | `docs/dev/PROGRESS.md`, `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md` |
| `operator-real-docs-task-170` | Operator submit/run flow succeeded through PR #60 and merge, but CI Guardian marked the task failed before pending checks completed. Evidence repair later made the operator-facing status recovered. | `docs/dev/PROGRESS.md`, `docs/dev/OPERATOR_SUBMIT_RUN_WORKFLOW.md` |
| `remote-docs-exec-pilot-001` | First remote docs pilot attempt failed before the later successful `remote-docs-exec-pilot-002` rerun. The later run exposed the same class of evidence drift: PR #57 recovered and merged after the task had already recorded an initial CI blocker. | `docs/dev/PROGRESS.md`, `docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md` |

## Taxonomy

### 1. Pending-Check False Failure

**Signature:** A child PR exists, changed files are low-risk, CI is still
pending or temporarily unavailable, and CI Guardian records the task as failed
before GitHub Actions reaches a final green state.

**Observed in:** `task_proposal-4212a5e1447212c0`,
`operator-real-docs-task-170`, and the recovered remote docs pilot.

**Operator recovery:**

1. Inspect the child PR, not only the raw task status.
2. Confirm all required checks eventually passed.
3. Confirm the PR merged and record the merge commit.
4. Repair task evidence with `recovered=true`, `ci_status=passed_after_pending`
   or `passed_after_rerun`, `risk_status=low_docs_only`, PR URL, merge commit
   and changed files.
5. Preserve the original failed task event. Do not rewrite history to
   `completed`.

### 2. Raw Failed, Recovered Evidence

**Signature:** `task.status` remains `failed`, but `evidence_summary.recovered`
is true and the PR/CI/merge evidence proves the task completed through a later
recovery path.

**Observed in:** `task_proposal-d90d09da925d2cf0`,
`task_proposal-4212a5e1447212c0`, and `operator-real-docs-task-170`.

**Operator recovery:**

1. Treat the task as operator-recovered when `recovered=true` and PR evidence is
   complete.
2. Use display status such as `recovered` or `failed/recovered` in operator
   views.
3. Keep raw status available for audit and root-cause analysis.
4. Do not requeue the task unless recovered evidence is absent or invalid.

### 3. Missing Evidence Status

**Signature:** A task has a failed raw status, but no usable
`evidence_summary`, no recovery flag, or no final CI classification. This often
appears after transport failures, API/version gaps, or a worker stops before
PR packaging.

**Observed in:** the initial `task_proposal-d90d09da925d2cf0` transport failure
before retry, and the first failed remote pilot attempt.

**Operator recovery:**

1. Determine whether a child PR exists.
2. If no child PR exists, classify the failure at the execution boundary, such
   as `codex_transport_eof`, auth unavailable, route missing, or no task
   processed.
3. If a child PR exists, inspect PR checks and merge state.
4. Add recovered evidence only when PR, CI and merge proof exists.
5. If evidence cannot be reconstructed safely, leave the task failed and create
   a follow-up task with explicit expected files and recovery criteria.

### 4. Missing Changed Files

**Signature:** The task result has a PR URL or CI status but lacks
`changed_files`, so low-risk classification, duplicate detection and planner
compact state cannot reason about the exact scope.

**Observed in:** historical pilot/recovery flows where the human-readable docs
identified changed files, but the task evidence did not consistently carry the
same structured field.

**Operator recovery:**

1. Prefer the worker's structured `changed_files` output when present.
2. If missing, reconstruct from the child PR file list.
3. Record only repository-relative paths, for example
   `docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md`.
4. Verify the files match the task's expected docs-only scope before marking
   `risk_status=low_docs_only`.
5. If files exceed scope, keep the task failed and open a review follow-up
   instead of repairing evidence.

### 5. Dependency Or Transport Failure Before Packaging

**Signature:** The worker claims or starts a task, but no PR is created because
the executor or platform fails first. Examples include Codex websocket/TLS/EOF
transport errors, missing cloud routes, missing worker auth, or GitHub checkout
403/account-suspended errors.

**Observed in:** `task_proposal-d90d09da925d2cf0` before the targeted retry and
the remote docs pilot sequence before recovery hardening.

**Operator recovery:**

1. Classify the boundary that failed: planner route, worker auth, executor
   transport, validation, PR packaging or CI.
2. Retry only bounded transient classes, such as known Codex transport errors
   or recoverable CI infrastructure failures.
3. Use targeted `PollOnce` with a single task id. Do not start a long-running
   worker loop for recovery.
4. Restore project control to `paused` after the attempt.
5. Record retry count and error class in evidence when the task still fails.

## Recovery Playbook

Use this sequence for a task that appears failed but may have completed through
a child PR:

1. Run compact status for the task and capture safe fields only: raw status,
   display status, PR URL, evidence status, CI status and changed files.
2. Inspect the child PR if present. Confirm checks, changed files, merge state
   and merge commit.
3. Match the task to one failure mode above.
4. For merged low-risk docs-only PRs, call the evidence repair path with:
   `recovered=true`, PR URL, merge commit, `changed_files`,
   `validation_status=passed`, final `ci_status`, `risk_status=low_docs_only`
   and a short safe summary.
5. For failures without a merged PR, keep the task failed, add the error class,
   and create a focused follow-up instead of fabricating recovery evidence.
6. Confirm project control is `paused`, `stop_requested=false`, and no
   unexpected queued/running residue remains.

Do not upload raw command output, raw Codex JSONL, prompts, patches, secrets or
local runtime snapshots as part of repair evidence. Evidence should remain a
concise normalized summary that is safe for SkyBridge storage and operator UI.

## Prevention Checklist

- CI Guardian should distinguish pending checks from final failures and avoid
  closing low-risk child tasks while checks are still in progress.
- Worker completion and repair payloads should always include `changed_files`
  when a PR exists.
- Planner compact state should include recovered tasks in `do_not_repeat` so
  Hermes and rule-based planners do not propose duplicate recovery work.
- Operator views should show both raw status and display status so historical
  failure and recovered proof are visible at the same time.
- Recovery retries should stay bounded: one targeted task, `PollOnce`,
  `MaxParallel=1`, and project control restored to `paused`.
