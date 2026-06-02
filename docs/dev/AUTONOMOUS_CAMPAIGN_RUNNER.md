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

Local runner state is stored under ignored `.agent/campaign-runners`:

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

Dry-run reports are written under ignored `.agent/tmp` by default. Goal 188A added `.agent/campaign-runners/` to `.gitignore`, so dry-run runner state should not dirty `git status`.

## Dev Queue Launch Wrapper

`scripts/powershell/start-dev-queue-189-200.ps1` accepts these queue launch parameters:

- `-GoalPackDir`, default `goals/dev-queue-189-200`
- `-CampaignId`, default `dev-queue-189-200`
- `-MaxSteps`, default `12`
- `-MaxTasks`, default `12`
- `-MaxRuntimeMinutes`, default `240`
- `-OutputDir`, default `.agent/tmp`
- `-OutputFile`, optional JSON runner report path
- `-DryRun`, optional explicit dry-run marker
- `-Apply`, required for actual execution

The wrapper returns resolved parameters in JSON when `-Json` is used. Dry-run can be validated from a clean feature branch. `-Apply` still requires clean latest `main`.

## Post-merge Launch

After Goal 188A is merged, reviewed and any required server deployment is complete, run from clean latest `main`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\start-dev-queue-189-200.ps1 `
  -GoalPackDir .\goals\dev-queue-189-200 `
  -CampaignId dev-queue-189-200 `
  -MaxSteps 12 `
  -MaxTasks 12 `
  -MaxRuntimeMinutes 240 `
  -Apply `
  -Json `
  -OutputFile .agent/tmp/dev-queue-189-200-runner-report.json
```

The script verifies clean latest `main`, validates and imports the queue, checks active tasks and stale leases, then starts `run-until-hold` with bounded limits and reports under `.agent/tmp`.

Do not run this command while the parent PR is draft/manual or before the expanded Goal 189-200 files are reviewed.

## Operator Watch And Control

Goal 188C adds two launch-day scripts:

- `scripts/powershell/skybridge-campaign-watch.ps1`: read-only Docker BuildKit-style live watch with spinner frames, colored statuses, current-step context, nearby queue entries and recent runner audit entries.
- `scripts/powershell/skybridge-dev-queue-control.ps1`: preflight/control wrapper for the dev queue.

Recommended two-window operation:

```powershell
# Window A: read-only watch
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command watch `
  -CampaignId dev-queue-189-200 `
  -PollIntervalSeconds 5 `
  -RenderIntervalMilliseconds 250 `
  -ColorMode Always

# Window B: control commands
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command preflight `
  -Json
```

Preview the watch UI without cloud mutation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign-watch.ps1 `
  -Demo `
  -Once `
  -ColorMode Always
```

Use `start-one` before `start-all`:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command start-one `
  -DryRun `
  -Json

# After review, from clean latest main only:
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command start-one `
  -Apply `
  -Json
```

If Goal 189 succeeds and the report is clean, start the remaining queue:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command start-all `
  -Apply `
  -Json
```

Use `safe-pause -Apply -Reason` for normal operator holds. Use `emergency-stop -Apply -Reason` only when the runner must stop quickly; it sets project stop requested and prints the instruction to press Ctrl+C in the runner window if it is still running. `resume -Apply` first returns project control to paused/no-stop state, refreshes worker heartbeat and resumes the bounded campaign runner.

Stale runner locks must be inspected before unlock:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command unlock-stale-runner `
  -Reason "inspected stale runner lock" `
  -Apply `
  -Json
```

The wrapper refuses to unlock an active non-stale runner lock.

## Goal 188D JSON And Watch Polish

Goal 188D hardens launch-day JSON handling. The control wrapper invokes child PowerShell scripts and those children can legitimately emit non-JSON diagnostic lines before their JSON payload, for example `git fetch` prefix lines on stderr. `skybridge-dev-queue-control.ps1` now first tries whole-output JSON parsing, then extracts the last JSON object or array from mixed output. Its JSON response includes `child_parse_mode` and `child_non_json_prefix_present` for `start-one` and `start-all` diagnostics. JSON mode remains valid JSON and must not include ANSI color or secrets.

`start-dev-queue-189-200.ps1` also quiets `git fetch` in the clean-main guard so expected fetch chatter does not contaminate JSON output.

The watch CLI now separates local rendering from remote polling:

- `-RenderIntervalMilliseconds` controls visual spinner smoothness.
- `-PollIntervalSeconds` controls remote API polling and defaults to 5 seconds.
- `-IntervalSeconds` remains a backward-compatible alias for `-PollIntervalSeconds`.
- `-MaxFrames` is useful for demos and smokes.

Recommended high-smoothness watch command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command watch `
  -CampaignId dev-queue-189-200 `
  -PollIntervalSeconds 5 `
  -RenderIntervalMilliseconds 250 `
  -ColorMode Always
```

After this fix, verify `start-one` before launching the full queue:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-dev-queue-control.ps1 `
  -Command start-one `
  -Apply `
  -Json
```

Do not run `start-all -Apply` until `start-one` has been reviewed and Goal 189 is confirmed clean.

## Goal 188E Resume, Residue And Lease Hardening

Goal 188E keeps Goal 190 unexecuted and hardens the runner before the next launch. Resume/start-one/start-all now classify existing step state before creating work:

- no linked task: `execute-step` may create exactly one task;
- linked queued/claimed/running task: wait and report the active task id;
- linked failed task plus linked PR: resume finalizer/evidence repair without creating another PR;
- linked merged PR missing evidence: repair evidence only;
- completed/recovered linked task but missing campaign step evidence: attach campaign step evidence only;
- completed/recovered/skipped step: skip by default;
- campaign already advanced: continue from the campaign current step and treat old runner failure as historical.

`runner-status` and `runner-report` now distinguish `current_blocker` from `historical_warning`. If `dev-queue-189-200` is current at Goal 190 and an old runner state failed on Goal 189, report it as historical residue, not a current runner failure.

Hygiene findings include concrete ids and classifications such as `repairable_residue`, `safe_to_ignore_for_metadata_advance`, `unsafe_for_worker_execution` and `manual_review_required`.
