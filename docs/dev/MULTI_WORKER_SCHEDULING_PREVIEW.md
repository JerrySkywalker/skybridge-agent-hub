# Multi-worker Scheduling Preview

Goal 206A adds preview-only worker distribution for BOINC-like managed mode. It models worker pools, availability, capability matching, scoring, repo parallelism, and route plans without creating claims, leases, tasks, PRs, or execution.

## Model

The shared contracts are:

- `skybridge.worker_profile.v1`
- `skybridge.worker_pool.v1`
- `skybridge.worker_availability.v1`
- `skybridge.worker_capability_match.v1`
- `skybridge.worker_score.v1`
- `skybridge.scheduling_preview.v1`
- `skybridge.repo_parallelism_policy.v1`
- `skybridge.workunit_route_plan.v1`
- `skybridge.multi_worker_readiness.v1`

Workers expose host, OS, architecture, group, supported task types, project/repo allowlists, available tools, resource policy summary, trust level, and `can_claim_tasks=false` / `can_execute_tasks=false`.

## Scheduling Preview

`scripts/powershell/skybridge-worker-scheduler.ps1` accepts fixture workunits and fixture workers, scores route options, and returns a preview route plan. Rejections include stale workers, disabled workers, busy workers, capability mismatches, project/repo mismatches, OS/tool mismatches, and repo parallelism blockers.

## Repo Parallelism

The preview policy is conservative:

```text
max_parallel_per_repo=1
mutating_work_serialized=true
uncertain_counts_as_mutating=true
```

Docs/local-smoke work counts as repo-mutating when it may modify files. Read-only parallelism is only previewed when explicitly marked read-only.

## Apply Disabled

Goal 206A does not authorize scheduling apply, task claim, lease creation, worker execution, or PR creation. Attention events are safe metadata only:

- `multi_worker_preview_available`
- `worker_stale`
- `worker_capability_mismatch`
- `repo_parallelism_blocks_concurrent_work`
- `scheduling_apply_disabled`

## Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-pool-schema-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-scheduler-route-plan.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-scheduler-preview-no-claim.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-scheduler-preview-no-lease.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-scheduler-preview-no-execution.ps1
```
