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
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command sanitized-executor-contract -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 -Command run-sanitized-executor -Json
```

Preview is read-only and never creates a task or claims work. The Goal 201B one-shot claim gate now proves the fixed campaign, goal, task type, budget, route, path allowlist, clean worktree, no open trial PR and second-claim refusal rules. Its `-Apply` mode records only safe local claim/lease evidence under ignored `.agent/tmp/...` state and is not a general queue claim API.

The one-shot executor gate uses a sanitized Codex boundary for Goal 201C. It invokes Codex only for the single `bootstrap-trial-201` docs/local-smoke task, feeds the bounded task prompt through stdin, discards process stdout/stderr without writing logs, and persists only safe metadata under ignored `.agent/tmp/bootstrap-trial-201-one-shot/`.

The executor records task id, worker id, command class, changed files, PR URL and evidence hashes. It does not persist the prompt, Codex transcript, stdout, stderr or raw shell session logs. It fails closed if raw log persistence is requested or if any task, campaign, path, PR or worker gate is outside the one-shot contract.

On Windows, the sanitized executor resolves the Codex launcher before starting the process. Direct `codex.exe` and Unix-style extensionless launchers run directly; `codex.cmd` and `codex.bat` run through `cmd.exe`; `codex.ps1` runs through `pwsh` when available or Windows PowerShell as a fallback. The safe resolver metadata records only launcher kind, command class, host executable name and redaction flags. It does not persist raw command lines, raw paths, stdout, stderr, prompts or transcripts, and it refuses unclassified launcher shapes.

## Current Hold

This infrastructure pass stages the reviewed trial and proves the claim gate plus sanitized executor stop condition. Actual execution is allowed only after the infrastructure PR is merged, local `main` is clean and latest, and the final preflight confirms every one-shot gate.

Required follow-up before execution:

- run `start-one-apply` exactly once for the bootstrap trial;
- run `run-sanitized-executor -Apply` exactly once;
- verify the task PR remains open for human review and touches only `README.md` or `docs/**`;
- keep the queue held after the PR is opened.

After the task PR opens, final state is `held_waiting_human_pr_review` and `token_printed=false`.
