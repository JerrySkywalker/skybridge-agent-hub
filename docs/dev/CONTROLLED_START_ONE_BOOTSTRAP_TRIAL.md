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
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command one-shot-claim-gate -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command one-shot-executor-gate -Json
```

Preview is read-only and never creates a task or claims work. The Goal 201B one-shot claim gate now proves the fixed campaign, goal, task type, budget, route, path allowlist, clean worktree, no open trial PR and second-claim refusal rules. Its `-Apply` mode records only safe local claim/lease evidence under ignored `.agent/tmp/...` state and is not a general queue claim API.

The one-shot executor gate remains fail-closed for actual execution because the current shared Codex executor persists local prompt/log artifacts (`prompt.md`, `codex-exec.jsonl` and validation logs). Goal 201B forbids persisting raw prompts, raw transcripts or raw worker logs for the trial path, so `start-one-apply` must remain held until a redacted executor path exists.

## Current Hold

This infrastructure pass stages the reviewed trial and proves the claim gate plus executor stop condition. It does not execute the trial because the current executor cannot yet satisfy the no-raw-prompt/log persistence boundary.

Required follow-up before execution:

- replace or harden the Codex executor path so it does not persist raw prompts, raw transcripts or raw worker logs for the bootstrap trial;
- then run the already-staged one-shot executor that can create at most one PR and then stop;
- record a lease outcome and safe evidence without raw transcripts or raw logs;
- keep the queue held after the PR is opened.

Until then, final state is `held_no_execution_executor_gate_blocked` and `token_printed=false`.
