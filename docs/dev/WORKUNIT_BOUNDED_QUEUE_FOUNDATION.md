# Workunit and Bounded Queue Foundation

Goal 204A introduces BOINC-like workunit vocabulary for SkyBridge Agent Hub. This is a preview foundation only. It does not create tasks, claim tasks, execute workers, create PRs, start runners, or expose bounded queue apply.

## Workunit

A workunit is the durable unit of future queue planning. It binds a project, campaign, goal, task id, task type, required capabilities, allowed paths, risk, retry policy, lease state, result artifacts, evidence artifacts, PR URL, and CI status.

The first fixture workunit maps the completed bootstrap task:

- `workunit_id`: `workunit-bootstrap-trial-201-task-001`
- `campaign_id`: `bootstrap-trial-201`
- `goal_id`: `goal-201-controlled-start-one-bootstrap-trial`
- `task_id`: `bootstrap-trial-201-task-001`
- `state`: `completed`
- `pr_url`: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124`

This mapping is historical. It must not recreate the task, rerun the executor, or create another PR.

## Campaign Step vs Workunit

A campaign step describes an operator-reviewed goal in a campaign ledger. A workunit describes a bounded executable item for future queue planning. Goal 204A links those concepts without enabling execution:

- campaign steps remain the review and reporting ledger;
- workunits provide BOINC-like state, leases, retries, result artifacts, and queue policy;
- bounded queue preview can show what would happen under policy;
- bounded queue apply remains unavailable.

## Bounded Queue Policy

The initial policy includes:

- `max_steps`
- `max_tasks`
- `max_prs`
- `max_runtime_minutes`
- `max_parallel_per_repo`
- `stop_on_pr_created`
- `stop_on_ci_failure`
- `stop_on_warning`
- `drain_after_current`
- `pause_after_current`
- `require_human_review`
- `allow_task_types`
- `block_task_types`

The fixture policy is intentionally narrow: one task, zero PRs, one repo worker, human review required, stop on warning/CI/PR, and token output disabled.

## Preview Commands

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-workunit-queue.ps1 -Command schema -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-workunit-queue.ps1 -Command preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-workunit-queue.ps1 -Command readiness -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-workunit-queue.ps1 -Command safe-summary -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-workunit-queue.ps1 -Command fixture-plan -Json
```

There is no `apply` command.

## Apply Disabled

Bounded queue apply is disabled because queue execution still needs future explicit authorization for task creation, task claiming, executor launch, PR creation, concurrency, leases, and conflict handling.

Readiness defaults:

- `can_start_bounded_queue=false`
- `start_bounded_queue_apply_available=false`
- blockers include `bounded_queue_apply_not_yet_enabled`
- blockers include `requires_future_goal_authorization`

## Future Path

Future BOINC-like mode can build on these contracts by adding reviewed workunit creation, lease recovery, bounded queue apply gates, operator confirmations, and resource-policy enforcement. That future work must preserve the no-secrets and bounded-execution safety model and must be authorized by a separate goal.
