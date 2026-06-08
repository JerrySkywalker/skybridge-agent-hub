# Multi-worker Readiness

Goal 197 adds a preview-only worker readiness and routing policy. It prepares selection for a later Controlled Start-One Bootstrap Trial, but it does not enable task claims, worker execution, queue start, campaign-step task creation, or worker loops.

## Capability Matrix

Each worker readiness record includes:

- `worker_id`, `worker_label`, `worker_profile`
- `os`: `windows`, `linux`, `macos`, or `unknown`
- `tools`: `codex`, `git`, `node`, `pnpm`, `rust`, `docker`, `powershell`, `bash`
- `task_type_capabilities`
- `project_access` and `repo_access`
- safe booleans for local smokes, frontend, backend, docs, and worker-service work
- `can_claim_tasks=false`
- `can_execute_tasks=false`
- `token_printed=false`

The fixture pool models a Windows standby worker, a Linux preview worker, a disabled docs worker, and a foreign-repo worker. These are local status fixtures, not execution identities.

## Readiness States

Worker readiness states are `online`, `offline`, `stale`, `disabled`, `busy`, and `unknown`. Readiness includes heartbeat age, `current_task_id`, service mode, readiness score, blockers, warnings, and a recommended action.

Offline, stale, disabled, and busy workers are rejected by route preview. Online workers may be selected only as preview candidates while `can_claim_tasks=false` and `can_execute_tasks=false`.

## Routing Policy

`skybridge-worker-routing.ps1` exposes read-only commands:

- `worker-capability-matrix`
- `worker-readiness`
- `worker-route-preview`
- `worker-route-fixture`
- `worker-routing-policy`
- `worker-readiness-summary`

The policy rejects:

- offline, stale, disabled, or busy workers;
- capability mismatches;
- project or repo access mismatches;
- OS/tool mismatches;
- active repo locks;
- stale repo locks until stale recovery happens first;
- repo parallelism above `max_parallel_per_repo=1`.

The selected worker is the highest readiness score among accepted preview candidates. Preview output always reports `task_created=false`, `task_claimed=false`, `task_executed=false`, `worker_loop_started=false`, `queue_execution_enabled=false`, and `token_printed=false`.

## Repo Parallelism Guard

Goal 197 keeps the Goal 196 repo-exclusive-lock model. `max_parallel_per_repo=1` is explicit in the routing policy and in route preview output. If a repo lock is active, preview is blocked. If the repo lock is stale, preview requires stale recovery first. If another campaign or worker owns the repo, preview is blocked.

## Attention Events

The readiness model derives these attention events without implying execution:

- `no_ready_worker`
- `all_workers_offline`
- `worker_stale`
- `worker_disabled`
- `capability_mismatch`
- `repo_parallelism_blocked`
- `selected_worker_ready_for_preview_only`

Desktop and Web render these as read-only attention and routing panels. They do not expose execution controls.

## Queue Control Integration

`queue_control_readiness` now includes `routing_readiness`. `can_start_one=false` and `can_start_queue=false` remain unchanged. A preview candidate produces a warning that worker selection is ready for preview only, while execution remains disabled until a future Controlled Start-One Bootstrap Trial.

## Remaining Before Start-One Trial

Before any controlled start-one trial, SkyBridge still needs an explicit execution gate, reviewed repo-lock recovery path, operator-approved task claim transition, audit evidence for the selected worker, and a bounded execution launch goal. Goal 197 intentionally stops before those actions.

## Goal 198 Project Policy Layer

Goal 198 layers project profile selection on top of worker route preview. A selected worker is not enough to execute work; route preview now carries the selected project profile hash and `project_selection_preview_only=true`.

The project policy layer validates repo roots, allowed and blocked paths, default branch, validation command shape, worker profile defaults and goal pack defaults before any future controlled start-one trial. `can_claim_tasks=false`, `can_execute_tasks=false`, `can_start_one=false` and `can_start_queue=false` remain unchanged.
