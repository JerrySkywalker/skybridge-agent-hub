# Controlled Start-One Bootstrap Trial

Goal 201 introduces a dedicated reviewed trial pack for the proposed Local README Refresh payload:

- proposed source: `goals/proposed/proposed-goal-201-local-readme-refresh.md`
- reviewed campaign: `goals/bootstrap-trial-201/campaign.skybridge.json`
- reviewed goal: `goals/bootstrap-trial-201/goal-201-controlled-start-one-bootstrap-trial.md`

The pack is intentionally one step only. It is not part of `dev-queue-189-200`.

## Contract

The trial budget is fixed:

- `max_steps=1`
- `max_tasks=1`
- `max_prs=1`
- `max_runtime_minutes=30`
- `max_parallel_per_repo=1`
- allowed task types: `docs`, `local-smoke`
- auto-merge: disabled
- continuation: disabled

`scripts/powershell/skybridge-bootstrap-trial-goal201.ps1` provides the local contract surface:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command contract -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command start-one-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command start-one-apply -Reason "operator authorized one-shot bootstrap trial" -Json
```

Preview is read-only and never creates a task or claims work. `start-one-apply` is explicitly blocked while the worker service and routing contracts still report `can_claim_tasks=false` and `can_execute_tasks=false`.

## Current Hold

This infrastructure pass stages the reviewed trial and proves the gate. It does not execute the trial because a real one-shot worker claim/executor boundary is not present yet.

Required follow-up before execution:

- add a one-shot worker claim path that can claim at most one Goal 201 docs/local-smoke task;
- add a one-shot executor that can create at most one PR and then stop;
- record a lease outcome and safe evidence without raw transcripts or raw logs;
- keep the queue held after the PR is opened.

Until then, final state is `held_no_execution_worker_claim_disabled` and `token_printed=false`.

