# Campaign Locking And Multi-campaign Queue

Goal 196 adds the campaign locking and multi-campaign queue review foundation. It does not enable queue execution.

## Contracts

Shared review models:

- `skybridge.campaign_lock.v1`
- `skybridge.repo_exclusive_lock.v1`
- `lock_owner`
- `heartbeat_at`
- `expires_at`
- `lock_status`: `active`, `stale`, `released`, `cancelled`, `aborted`, `held`
- `release_reason`
- `operator_reason`
- `campaign_id`
- `project_id`
- `repo_id` / `worktree_identity`
- `token_printed=false`

The priority queue model is `skybridge.campaign_priority_queue.v1`. It enforces one active campaign per project in the review model, sorts deterministically by priority, filters `ready`, `paused`, `held`, `completed` and `archived`, and returns a queue decision summary without side effects.

## Repo-exclusive Lock Policy

Only one campaign, runner or worker may own the repo mutation lock for a worktree. An active repo lock blocks start-one and start-queue previews. A stale repo or campaign lock must be inspected first and can be released only with an operator reason. Active non-stale locks cannot be force-released.

The lock review output is safe to display. It includes owner identity, heartbeat age, expiry, release reason, operator reason and whether the lock blocks execution previews. It excludes tokens, Authorization headers, raw prompts, stdout/stderr and worker logs.

## Stale Recovery

Recovery is inspection-first:

1. Run a lock preview.
2. Confirm owner, heartbeat age and expiry.
3. Apply stale unlock only with `-Reason`.
4. Record release reason and audit evidence under ignored local fixture paths.

The fixture apply path writes only safe local audit metadata and never starts workers, claims tasks or creates campaign-step tasks.

## Cancel / Abort / Hold

Cancel, abort and hold are reason-gated state semantics:

- cancel is for a campaign before execution;
- abort records campaign-run state without killing arbitrary processes;
- hold pauses the campaign for operator review.

All three require a reason in preview and apply mode. They write safe audit or fixture evidence only and do not create tasks or start workers.

## CLI

Use `skybridge-dev-queue-control.ps1`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command campaign-lock-status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command campaign-lock-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command repo-lock-status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command repo-lock-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command unlock-stale-campaign-lock -Reason "inspected stale lock" -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command campaign-priority-queue -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 -Command campaign-select-next-preview -Json
```

Default mode is dry-run/read. Apply requires a reason and remains local/fixture-safe for this goal.

## Desktop And Web

Desktop and Web render lock review panels with campaign lock status, repo lock status, owner, heartbeat age, expiry, stale recovery guidance and priority queue selection. They expose no execution controls. Web has no local process control.

## Attention And Readiness

Attention events derive from active repo lock blockers, stale lock review, cancelled/aborted/held campaign state, multi-campaign conflicts, unknown lock owners and missing unlock reasons.

`queue_control_readiness` includes lock blockers:

- active repo lock blocks start previews;
- stale lock blocks start until reviewed;
- multiple ready campaigns produce selection warnings;
- `can_start_one=false`;
- `can_start_queue=false`;
- execution apply remains disabled until a later reviewed multi-worker readiness gate.

## Goal 197

Goal 197 can build multi-worker readiness on top of these locks. Goal 196 only adds inspection, preview, reason-gated local recovery semantics and UI review panels.
