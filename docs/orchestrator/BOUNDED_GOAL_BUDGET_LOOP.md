# Bounded Goal Budget Loop

MG356 adds the first bounded loop controller for SkyBridge campaign
orchestration. It chooses exactly one safe next action per invocation and then
stops.

## Purpose

The bounded loop connects the previous milestones without becoming a queue
runner:

- MG351 defines provider inventory and execution ownership.
- MG352 proves one server-selected safe local step can run once.
- MG353 proves ordered static multi-step sequencing.
- MG354 generates one proposed goal markdown candidate and holds it.
- MG355 reviews and appends one generated goal as metadata only.

MG356 decides between those paths in a deterministic order. It does not ask an
LLM to plan the action, does not approve generated goals, and does not execute an
appended goal in the same invocation.

## Controller

Script:

```powershell
scripts/powershell/skybridge-bounded-goal-loop.ps1
```

Commands:

- `status`
- `preview`
- `apply-one`
- `run-fixture-scenario`
- `report`
- `safe-summary`

Default mode is fixture preview. Mutations require:

```text
I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY
```

Optional local Codex generation inside the loop also requires:

```text
I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION
```

Appending a reviewed candidate inside the loop is scoped to reviewed metadata
only and may be paired with:

```text
I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION
```

## Action Selection

The policy is deterministic:

1. Reject hard blockers such as invalid budget, unsafe limits, stale or active
   unrelated work, unsafe candidate state, or missing provider for a selected
   execution.
2. If a ready campaign step exists, select `execute_ready_step`.
3. Else if a reviewed candidate exists and budget remains, select
   `append_reviewed_goal`.
4. Else if budget remains, select `generate_proposed_goal`.
5. Else select `hold`.

`MaxActionsPerRun`, `MaxStepsPerRun`, and `MaxGeneratedGoalsPerRun` are capped at
`1`. Values above `1` are rejected.

## Budget Semantics

Generation does not consume goal budget. The generated markdown still requires
human review and a later append gate.

Append consumes one budget unit because it changes campaign metadata by adding a
future step. The appended step remains `pending` and is not executed in the same
loop invocation.

Ready-step execution does not consume goal budget. It advances an existing
campaign step.

## Fixture Scenarios

Scenario A, ready step:

- campaign: `bounded-loop-fixture-ready-step-356`
- step: `bounded-loop-safe-step-356-001`
- task: `bounded-loop-safe-task-356-001`
- selected action: `execute_ready_step`
- result: one safe task is simulated as created, claimed, completed, and
  evidenced.

Scenario B, reviewed candidate:

- campaign: `bounded-loop-fixture-reviewed-candidate-356`
- candidate: `generated-goal-355-fixture`
- selected action: `append_reviewed_goal`
- result: one pending metadata step is appended, budget changes from `1` to `0`,
  and no task is created.

Scenario C, generate:

- campaign: `bounded-loop-fixture-generate-356`
- generated goal: `bounded-loop-generated-goal-356-fixture`
- selected action: `generate_proposed_goal`
- result: one proposed markdown candidate is written under `.agent/tmp`, budget
  remains unchanged, and the candidate is not reviewed, appended, or executed.

Scenario D, budget exhausted:

- campaign: `bounded-loop-fixture-budget-exhausted-356`
- selected action: `hold`
- result: no generation, append, execution, or worker loop.

## Optional Live Flow

MG356 supports live preview as a read-only checkpoint. Live apply remains
deferred unless every precondition is explicit and a future goal authorizes the
specific selected action. A live invocation must still select at most one action.

## Safety Boundaries

The bounded loop does not implement:

- unbounded loops;
- queue runners;
- worker loops;
- generated goal auto-approval;
- generated goal auto-append;
- appended goal execution in the same invocation;
- Hermes planning;
- MCP execution;
- arbitrary shell surfaces;
- arbitrary Codex prompts;
- arbitrary MATLAB commands;
- release, tag, asset, or production infrastructure mutation.

Reports include sanitized booleans, counts, safe paths, hashes, blockers, and
warnings. They do not include raw prompts, raw logs, stdout, stderr, credentials,
cookies, provider auth headers, proxy profiles, or complete environment
listings.

Every report must include `token_printed=false`.

## Manual M6 Test

Script:

```powershell
scripts/powershell/manual-bounded-goal-loop-test.ps1
```

Fixture checklist:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-bounded-goal-loop-test.ps1 -Fixture -Scenario ready-step -Preview -Json -WriteReport
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-bounded-goal-loop-test.ps1 -Fixture -Scenario ready-step -ApplyOne -Confirm I_UNDERSTAND_RUN_ONE_BOUNDED_GOAL_LOOP_ACTION_ONLY -Json -WriteReport
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-bounded-goal-loop-test.ps1 -Fixture -Scenario reviewed-candidate -Preview -Json -WriteReport
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-bounded-goal-loop-test.ps1 -Fixture -Scenario generate -Preview -Json -WriteReport
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-bounded-goal-loop-test.ps1 -Fixture -Scenario budget-exhausted -Preview -Json -WriteReport
```

The operator verifies one action per apply, no execution after append, no worker
loop, no Hermes or MCP call, and `token_printed=false`.

## Next Milestone

MG357 can pilot Hermes as an optional planner provider. MG359 can pilot managed
development PR flow if the operator prioritizes repository mutation controls
before planner work.
