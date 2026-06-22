# Start-One Apply Pilot

Mega Goal 319 introduces a single-task apply pilot for the start-one path.
It is not batch execution and it is not `run-until-hold`.

The only allowed pilot task id is:

```text
start-one-apply-pilot-docs-001
```

The task is intentionally low risk and limited to:

```text
docs/operations/START_ONE_APPLY_PILOT.md
```

It must not deploy, mutate Docker runtime, touch server-root configuration,
read or write secrets, change OpenResty, Authelia, DNS, Cloudflare, GitHub
settings, branch protection or production services.

## Seed

Preview is the default:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-seed-start-one-pilot-task.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Preview `
  -Json
```

Live seed apply is post-merge only and requires the exact confirmation string:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-seed-start-one-pilot-task.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Apply `
  -Confirm I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK `
  -Json
```

The output schema is `skybridge.start_one_pilot_seed.v1`.

## Apply Pilot

Preview is the default:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-start-one-apply-pilot.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Preview `
  -Json
```

Live apply is post-merge only and requires the exact confirmation string:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-start-one-apply-pilot.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Apply `
  -Confirm I_UNDERSTAND_START_ONE_SINGLE_SAFE_TASK_ONLY `
  -Json
```

The output schema is `skybridge.start_one_apply_pilot.v1`.
Preview includes a sanitized `pilot_task_lookup` object that compares direct
task lookup, project task-list visibility and hygiene classification. If these
sources disagree on returned task fields, the pilot fails closed instead of
claiming a task.

## Safety Contract

The pilot may select only one candidate:

- `task_id=start-one-apply-pilot-docs-001`
- `status=queued`
- `risk=low`, or `risk=not_reported` only when the deterministic pilot task has
  explicit safe pilot hygiene proof;
- `task_type=docs` or `test`
- allowed path exactly `docs/operations/START_ONE_APPLY_PILOT.md`
- worker capability match for `jerry-win-local-01`

The output must prove:

- old failed and blocked Goal 315/317 residue stayed excluded;
- `remote-docs-exec-pilot-001` stayed excluded;
- no old task was claimed or requeued;
- `project_control` stayed paused;
- `run_until_hold_called=false`;
- `campaign_metadata_advanced=false`;
- `token_printed=false`.

Self-bootstrap convergence may distinguish the queued deterministic pilot task
from generic active tasks. The exception is limited to
`start-one-apply-pilot-docs-001` when hygiene reports it as
`active_ok`/`not-residue`; arbitrary active tasks remain blockers.

If the candidate is missing, unsafe, duplicated, blocked by residue, fails to
claim, fails execution, misses evidence, fails validation or leaks token-like
content, the pilot fails closed. It must not pick a second task or retry
indefinitely.

## Goal 320 Hardening

Goal 320 must harden duplicate-claim prevention, lease recovery, evidence
retention, notification holds, operator review UX, task PR behavior and
server-side policy enforcement before any batch execution or `run-until-hold`
path can be considered.

## Smokes

```powershell
corepack pnpm smoke:start-one-pilot-seed
corepack pnpm smoke:start-one-apply-pilot
```

## Mega Goal 319 One-Task Boundary Proof

This operations note proves only the Goal 319 start-one apply pilot boundary.
It does not authorize generic `start-one`, `start-all`, `run-until-hold`,
worker loops, production deployment, secret changes, GitHub settings changes or
infrastructure mutation.

The pilot is bounded to exactly one deterministic docs task:

- task id exactly `start-one-apply-pilot-docs-001`;
- task type `docs`;
- only allowed path `docs/operations/START_ONE_APPLY_PILOT.md`;
- no code, script, secret, deployment, GitHub settings or infrastructure paths;
- `project_control` stays paused outside the explicitly confirmed single-task
  apply path;
- the operator confirmation must be exactly
  `I_UNDERSTAND_START_ONE_SINGLE_SAFE_TASK_ONLY`.

Any mismatch is a stop condition. If the selected task id, task type, allowed
path, dirty-worktree state, active lock state, hygiene result, confirmation
string or forbidden action list differs from the values above, the pilot must
remain in preview/blocked state and no task may be claimed or executed.

Successful Goal 319 evidence is therefore narrow: the system may prove that one
reviewed docs-only task can be selected and applied once under the explicit
confirmation gate, then return to hold. It must not prove or imply that the
general queue, batch execution, server operation, production infrastructure or
future arbitrary tasks are authorized.

The smokes are fixture-only. They do not claim live tasks, do not run live
Codex, do not unpause project control and do not call `run-until-hold`.
