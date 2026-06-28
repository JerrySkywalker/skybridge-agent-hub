# Multi-Step Static Goal Loop

MG353 adds the first static multi-step campaign loop controller for SkyBridge.

The milestone is:

```text
M3: Multi-Step Static Campaign Manual Test
```

The controller proves one bounded ordered path:

```text
server campaign
-> preview-next
-> exact-confirmed apply-next
-> one selected step
-> one selected task
-> sanitized evidence attached to that step
-> repeat manually for the next fixed step
-> campaign completed after the third step
```

## Static, Not A Queue Runner

`skybridge-multi-goal-loop.ps1` is not an autonomous queue runner. Each
`apply-next` invocation selects at most one ready step, creates or completes at
most one task, writes evidence for that step and exits. It does not poll,
daemonize, run until idle, generate goal markdown, append goals, call planners,
start a worker service, start a worker loop, create PRs or auto-merge.

## Relation To MG351

MG351 introduced `skybridge.tool_provider.v1`. MG353 consumes that inventory
before preview and apply. Direct provider availability is required for the
selected static step. MATLAB and Codex detection are checked only for live
MATLAB/Codex steps. Hermes unavailability does not block this direct-provider
campaign, and MCP remains future/disabled.

Provider inventory remains evidence only. It does not authorize arbitrary
commands, arbitrary Codex prompts or arbitrary MATLAB commands.

## Relation To MG352

MG352 proved one campaign step with `safe-local-smoke.v1`. MG353 reuses the same
one-step apply discipline and adds:

- ordered static step selection;
- dependency gates between steps;
- per-step evidence;
- campaign completion only after the last step;
- the M3 manual script.

## Exact IDs

Fixture campaign:

- campaign: `local-cloud-static-multi-goal-fixture`
- worker: `mg353-fixture-worker`

Fixture steps:

1. `safe-local-smoke-step-353-001`
   - task: `static-multi-goal-safe-task-fixture-353-001`
   - template: `safe-local-smoke.v1`
   - runner: `safe-local-smoke-runner.v1`
2. `matlab-golden-step-353-002`
   - task: `static-multi-goal-matlab-task-fixture-353-002`
   - template: `matlab-parameter-sweep.v1`
   - runner: `matlab-parameter-sweep-runner.v1`
3. `codex-report-step-353-003`
   - task: `static-multi-goal-codex-task-fixture-353-003`
   - template: `codex-analysis-report.v1`
   - runner: `codex-analysis-report-runner.v1`

Live campaign:

- campaign: `live-static-multi-goal-loop-353-001`
- worker: `jerry-win-local-01`

Live steps:

1. `live-static-safe-step-353-001`
   - task: `live-static-safe-task-353-001`
   - template: `safe-local-smoke.v1`
   - runner: `safe-local-smoke-runner.v1`
2. `live-static-matlab-step-353-002`
   - task: `live-static-matlab-task-353-002`
   - template: `matlab-parameter-sweep.v1`
   - runner: `matlab-parameter-sweep-runner.v1`
3. `live-static-codex-step-353-003`
   - task: `live-static-codex-task-353-003`
   - template: `codex-analysis-report.v1`
   - runner: `codex-analysis-report-runner.v1`

## Dependency Rules

The next step is the first incomplete step whose dependencies are complete.

- Step 1 has no dependency.
- Step 2 requires step 1 completion.
- Step 3 requires step 2 completion.
- Campaign completion is allowed only after step 3 completion.

Explicit `-StepId` selection still goes through the same dependency gate and
blocks if an earlier step is incomplete.

## Gate Rules

`apply-next` requires:

- `MaxSteps=1`;
- exactly one selected step;
- exactly one selected task;
- supported template and runner id;
- direct provider inventory checked;
- selected provider available;
- no active task blocker;
- no stale lease blocker;
- exact confirmation.

Fixture confirmation:

```text
I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY
```

Live confirmation:

```text
I_UNDERSTAND_RUN_ONE_LIVE_STATIC_MULTI_GOAL_STEP_ONLY
```

## Fixture Flow

Fixture mode is CI-safe. It requires no live cloud, Codex, MATLAB, Hermes, MCP
or local worker service. It simulates the three fixed steps and records sanitized
evidence without invoking Codex or MATLAB.

Preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-multi-goal-loop.ps1 `
  -Command preview-next `
  -Fixture `
  -Json
```

Apply one step:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-multi-goal-loop.ps1 `
  -Command apply-next `
  -Fixture `
  -Confirm I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY `
  -Json `
  -WriteReport
```

Run the apply command three times to complete the fixture campaign. Each
invocation completes exactly one step and reports `token_printed=false`.

## Live Flow

Live mode is optional and skips safely when preconditions fail. It requires:

- configured `ApiBase`;
- present `TokenFile`;
- worker id `jerry-win-local-01`;
- worker online or recently heartbeated;
- direct provider inventory available;
- required provider detected for the selected live step;
- no active unrelated task;
- no stale active lease;
- exact MG353 ids;
- exact confirmation;
- `MaxSteps=1`.

Live preview performs no mutation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-multi-goal-loop-test.ps1 `
  -Live `
  -Preview `
  -WorkerId jerry-win-local-01 `
  -Json `
  -WriteReport
```

Live apply is one step per invocation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-multi-goal-loop-test.ps1 `
  -Live `
  -ApplyNext `
  -WorkerId jerry-win-local-01 `
  -MaxSteps 1 `
  -Confirm I_UNDERSTAND_RUN_ONE_LIVE_STATIC_MULTI_GOAL_STEP_ONLY `
  -Json `
  -WriteReport
```

If a precondition fails, the controller reports blockers and stops. It does not
retry or select another task.

## Evidence

Evidence uses:

```text
skybridge.multi_goal_loop_evidence.v1
```

Required safety values:

- `provider_inventory_checked=true`
- `direct_provider_available=true`
- `task_claimed_count=1`
- `execution_started=true`
- `execution_completed=true`
- `execution_failed=false`
- `codex_run_called=false` in fixture reports
- `matlab_run_called=false` in fixture reports
- `hermes_run_called=false`
- `mcp_run_called=false`
- `arbitrary_shell_enabled=false`
- `worker_loop_started=false`
- `project_control_unpaused=false`
- `token_printed=false`

Evidence may include only sanitized artifact paths and compact validation
summaries. It must not include process streams, prompts, logs, tokens,
credentials, cookies, provider headers, proxy profiles or complete env listings.

## Manual M3 Test

Use the manual wrapper:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-multi-goal-loop-test.ps1 `
  -Fixture `
  -Preview
```

Then apply one step at a time:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-multi-goal-loop-test.ps1 `
  -Fixture `
  -ApplyNext `
  -Confirm I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY `
  -WriteReport
```

Checklist:

- run fixture preview;
- run fixture apply-next for step 1;
- run fixture apply-next for step 2;
- run fixture apply-next for step 3;
- verify campaign completed;
- verify each step has evidence;
- verify no unbounded loop;
- verify no Hermes/MCP;
- optionally run live preview;
- optionally run live apply-next one step at a time;
- verify `token_printed=false`.

## Safe Skip Conditions

Live apply should skip safely when API configuration, token file, worker
heartbeat, provider inventory, exact ids, dependencies, provider availability,
task state or exact confirmation are missing. Fixture proof remains valid when
live mode is skipped.

## Reports

When `-WriteReport` is used:

- `.agent/tmp/multi-goal-loop/multi-goal-loop.md`
- `.agent/tmp/multi-goal-loop/multi-goal-loop.json`

## Next Milestone

MG354 adds the local Codex goal markdown generator as a separate authoring
surface. It can draft one reviewed markdown candidate, but it does not append,
import or execute the generated goal. See
[LOCAL_CODEX_GOAL_GENERATOR.md](LOCAL_CODEX_GOAL_GENERATOR.md).

MG355 adds the metadata bridge for those generated candidates. It validates and
approves or rejects one candidate, previews one append and can append one
pending campaign step, but the multi-step controller remains the execution
surface for fixed templates only. See
[GOAL_APPEND_REVIEW_IMPORT.md](GOAL_APPEND_REVIEW_IMPORT.md).

`token_printed=false`
