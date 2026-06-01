# Autonomous Campaign Runner

Goal 188 adds a bounded campaign runner around the existing campaign pack, step executor, worker, PR/CI and Hermes gate primitives.

## Commands

- `run-next`: plans or executes at most one current campaign step.
- `run-until-hold`: loops until completion, hold, blocker, failure, operator stop or configured limit.
- `run-until-complete`: same loop with campaign completion as the target.
- `resume`: continues from runner state when runner-specific arguments are supplied; it does not duplicate already attempted work.
- `runner-status`: reports runner state, lock state, current step and blockers.
- `runner-report`: writes Markdown or JSON runner reports.
- `runner-stop`, `runner-hold`, `runner-unlock`: explicit operator controls. Unlock requires `-Apply` and a reason.

Mutating commands remain dry-run by default. Use `-Apply` only after status and hygiene checks are clean.

## State And Locks

Local runner state is stored under `.agent/campaign-runners`:

- `*.runner.json`: runner id, campaign id, project id, status, step/task counts, last decision, hold reason, resume hash, approval scope and audit log.
- `locks/*.lock.json`: campaign lock id, owner, active/released/stale status, heartbeat, expiry and release reason.

Only one active runner lock is allowed per campaign/project. A stale lock blocks auto-run until inspected and released with `runner-unlock -Apply -Reason`.

## Safety Stops

The runner stops or holds on active tasks, stale leases, stale locks, dirty repo for live campaigns, missing approval, unsafe task type/path, real CI failure, missing evidence, uncertain gate result, max steps/tasks/runtime or operator stop.

The runner does not execute production deploy, secret rotation, server root config, GitHub settings or branch protection goals.

## Approval Scope

`-HumanApproved -HumanApprovalReason` creates a bounded `RunnerApprovalScope` for the campaign. The scope can satisfy per-step human approval only when the goal/task/path/limit policy matches. Delegated approval cannot override deterministic hard veto.

## PR Finalizer

`skybridge-pr-finalize.ps1` detects PR state, changed files and CI classification. It waits/blocks on pending or unknown state, retries transient failures once, blocks real CI failures and unsafe files, marks safe draft PRs ready, optionally enables auto-merge, and can repair task evidence after merge.

## Post-merge Launch

After Goal 188 is merged and deployed, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-dev-queue-189-200.ps1 -Apply -Json
```

The script verifies clean latest `main`, validates and imports the queue, checks active tasks and stale leases, then starts `run-until-hold` with bounded limits and reports under `.agent/tmp`.
