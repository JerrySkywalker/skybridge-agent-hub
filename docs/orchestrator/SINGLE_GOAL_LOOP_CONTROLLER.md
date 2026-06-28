# Single Goal Loop Controller

MG352 adds the first Local+Cloud single-goal loop bridge for SkyBridge.

The milestone is:

```text
M2: Single Goal Loop Manual Test
```

The controller proves one bounded path:

```text
server campaign step
-> local preview-once
-> exact-confirmed apply-once
-> one safe-local-smoke.v1 task
-> one claim/start/complete through safe-local-smoke-runner.v1
-> sanitized evidence attached to the campaign step
-> step completed
-> one-step campaign completed or held
```

## Relation To MG351

MG351 introduced `skybridge.tool_provider.v1` and the local provider inventory.
MG352 consumes that inventory before apply. The direct provider must be
available, but provider availability is still only evidence. It does not
authorize arbitrary execution.

Hermes remains optional. Hermes unavailability does not block
`safe-local-smoke.v1`. MCP remains future/disabled and is not contacted.
Codex and MATLAB detection never authorizes Codex or MATLAB execution for this
milestone.

## Why This Is Not A Worker Loop

`skybridge-goal-loop.ps1` runs one command and exits. It does not poll a queue,
start a daemon, requeue old work, fan out tasks, create PRs, generate goal
markdown, call planners, or run a multi-step campaign.

Apply is exact scoped:

- one campaign id;
- one step id;
- one task id;
- one worker id;
- one template: `safe-local-smoke.v1`;
- one runner: `safe-local-smoke-runner.v1`;
- one evidence attachment.

## Exact IDs

Fixture mode uses:

- campaign: `local-cloud-single-goal-fixture`
- step: `safe-local-smoke-step`
- task: `single-goal-safe-local-smoke-fixture-task`
- worker: `mg352-fixture-worker`

Live mode uses:

- campaign: `live-single-goal-loop-352-001`
- step: `safe-local-smoke-step-352-001`
- task: `live-single-goal-loop-safe-task-352-001`
- worker: `jerry-win-local-01`

## Fixture Flow

Fixture mode requires no cloud server. It simulates one campaign, one step, one
task candidate and one safe runner completion. It covers:

- preview creates no mutation;
- apply without exact confirmation is rejected;
- `MaxTasks > 1` is rejected;
- multiple candidate tasks are rejected;
- unsafe, Codex and MATLAB templates are rejected;
- active task, stale lease and dependency blockers are represented;
- evidence is sanitized and `token_printed=false`.

Preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-loop.ps1 `
  -Command preview-once `
  -Fixture `
  -Json
```

Apply once:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-loop.ps1 `
  -Command apply-once `
  -Fixture `
  -Confirm I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY `
  -Json `
  -WriteReport
```

## Live Flow

Live mode is optional and exact-id gated. Preconditions:

- `ApiBase` resolves to SkyBridge Server;
- `TokenFile` is present;
- worker id is `jerry-win-local-01`;
- provider inventory reports direct provider available;
- campaign, step and task ids match the MG352 exact ids;
- no active target task or stale lease blocks the run;
- exact confirmation is supplied.

Live preview performs no mutation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-single-goal-loop-test.ps1 `
  -Live `
  -Preview `
  -WorkerId jerry-win-local-01 `
  -Json `
  -WriteReport
```

Live apply is one-shot:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-single-goal-loop-test.ps1 `
  -Live `
  -Apply `
  -WorkerId jerry-win-local-01 `
  -Confirm I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY `
  -Json `
  -WriteReport
```

If a precondition fails, the controller reports blockers and exits without
retrying.

## Evidence Contract

Evidence attached to the campaign step uses:

```text
skybridge.single_goal_loop_evidence.v1
```

Required safety values:

- `task_claimed_count=1`
- `execution_started=true`
- `execution_completed=true`
- `execution_failed=false`
- `changed_files=[]`
- `codex_run_called=false`
- `matlab_run_called=false`
- `hermes_run_called=false`
- `mcp_run_called=false`
- `arbitrary_shell_enabled=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `token_printed=false`

Evidence and reports must not include process streams, prompts, logs, tokens,
credentials, cookies, provider headers, proxy profiles or complete env listings.

## Manual M2 Test

Use:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-single-goal-loop-test.ps1 `
  -Fixture `
  -Preview
```

Then apply once only after reviewing the preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-single-goal-loop-test.ps1 `
  -Fixture `
  -Apply `
  -Confirm I_UNDERSTAND_RUN_ONE_SINGLE_GOAL_LOOP_SAFE_TASK_ONLY `
  -WriteReport
```

The checklist verifies one campaign, one step, one safe-local-smoke task
candidate, task completion, evidence attachment, step completion, campaign
completion or hold, no Codex/MATLAB/Hermes/MCP and `token_printed=false`.

## Failure And Hold Cases

The controller holds or blocks instead of continuing when it sees:

- missing direct provider inventory;
- missing live API or token file;
- unexpected ids;
- worker unavailable;
- multiple candidate tasks;
- active task;
- stale lease;
- incomplete dependency;
- unsafe, Codex or MATLAB template;
- missing exact confirmation.

## Reports

When `-WriteReport` is used:

- `.agent/tmp/single-goal-loop/single-goal-loop.md`
- `.agent/tmp/single-goal-loop/single-goal-loop.json`

## Next Milestone

MG353 extends this single-step proof into a static three-step campaign loop:
safe-local-smoke, fixed MATLAB parameter sweep and fixed Codex analysis report.
It preserves the same one-step-at-a-time apply gate and remains separate from
goal generation, goal append/import and worker-loop execution. See
[MULTI_STEP_STATIC_GOAL_LOOP.md](MULTI_STEP_STATIC_GOAL_LOOP.md).

MG354 keeps goal generation on the other side of that boundary. The local Codex
goal generator can draft one markdown candidate for human review, but it cannot
import, append, approve or execute that candidate. See
[LOCAL_CODEX_GOAL_GENERATOR.md](LOCAL_CODEX_GOAL_GENERATOR.md).

MG355 adds review/import/append metadata handling for one generated candidate.
It does not extend this single-goal loop: appended generated steps remain
pending for a later explicit controller and no task is created or claimed during
append. See [GOAL_APPEND_REVIEW_IMPORT.md](GOAL_APPEND_REVIEW_IMPORT.md).
