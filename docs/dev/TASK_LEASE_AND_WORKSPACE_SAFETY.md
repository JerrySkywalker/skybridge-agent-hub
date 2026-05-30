# Task Lease And Workspace Safety

Super Goal 182 adds task lease and local workspace safety hardening before wider worker-loop batches.

## Task Lease Model

A task lease is stored on the task detail JSON and includes:

- `lease_id`
- `task_id`
- `worker_id`
- `project_id`
- `claimed_at`
- `lease_expires_at`
- `heartbeat_at`
- `lease_status`
- `current_attempt`
- `max_attempts`
- `stale_reason`

`lease_status` is one of `active`, `released`, `expired` or `abandoned`.

Claiming a task creates an active lease while keeping the legacy `claim` object for compatibility. Starting a task refreshes the lease heartbeat and expiry. Completing, failing or blocking a task releases the lease. Worker heartbeat refreshes the current active lease for that worker.

Expired active leases block duplicate claim attempts and are marked `expired` with `stale_reason=lease_expires_at_elapsed`. This goal does not automatically requeue stale tasks; stale recovery must be explicit and operator-visible.

## Worker Execution Gate

The edge worker now refuses to start Codex unless the claimed task includes an active lease for the current worker. This prevents a newer worker from silently executing against a cloud control plane that has not yet deployed task lease support.

If the lease guard fails, the worker blocks the task with clear evidence and stops before Codex execution.

## Repo Lock

The edge worker creates a local lock file before task execution:

```text
.agent/locks/skybridge-edge-worker.lock.json
```

The lock records `task_id`, `worker_id`, `pid` and `created_at`. A live non-stale lock blocks task execution. A stale lock is archived with a timestamped `.stale.<timestamp>.json` suffix before a new lock is acquired.

The lock is released in `finally`, including worker failures.

## Workspace Guards

Before Codex starts, the worker checks:

- dirty worktree: uncommitted repo changes block execution;
- active PR: a task with an existing child PR URL is not executed again;
- active branch: a task branch for another task or a colliding task branch blocks execution;
- active lease: claimed task must carry an active lease for this worker.

Worker logs remain isolated under:

```text
.agent/workers/<worker>/<task>/
```

## Status Visibility

`skybridge-status.ps1` now accepts:

- `-ShowLeases`
- `-ShowLocks`

`-ShowLeases` adds lease counts to the task summary and displays lease rows for shown tasks. Task detail JSON includes the raw `lease` object when the server provides it.

`-ShowLocks` is reserved for local/operator lock visibility; local lock files remain under `.agent/locks/` and are not committed.

## Safety Invariants

- Worker parallelism for `laptop-zenbookduo` remains `1`.
- A claimed task must have an active lease before Codex starts.
- A dirty worktree blocks execution before Codex starts.
- Existing child PR evidence blocks duplicate PR creation for the same task.
- Stale leases and stale locks are detected and reported; they are not silently retried through destructive cleanup.
