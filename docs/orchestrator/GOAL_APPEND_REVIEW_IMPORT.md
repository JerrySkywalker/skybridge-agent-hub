# Goal Append Review And Import

MG355 adds the first metadata-only bridge between local generated goal markdown
and SkyBridge campaign metadata. It takes one generated candidate, validates it,
records review state, previews an append, and can append exactly one reviewed
step with explicit confirmation. The appended step remains non-executed.

This milestone connects MG354 authoring to later campaign budget loops. It does
not run the generated goal and does not create or claim tasks.

## Relation To MG354

MG354 creates proposed markdown only. MG355 is the first layer that can review
that markdown and stage it for campaign metadata:

- review-preview validates a candidate without writing state;
- approve records a reason-gated review decision;
- append-preview proposes one campaign step without mutation;
- append-apply writes one non-running metadata step after exact confirmation.

MG355 must never call Codex to regenerate a missing or invalid candidate. If the
MG354 local candidate is unavailable, use the deterministic fixture candidate
and report the local-candidate blocker.

## Relation To Loop Controllers

MG352 and MG353 execute fixed, allowlisted steps one at a time. MG355 stays on
the metadata side of that boundary. It can append a reviewed generated goal as a
future campaign step, but it cannot execute that step, create a task for it,
claim a task, start a queue runner or start a worker loop.

Execution remains the responsibility of later exact-confirmed loop controllers.

## Controller

Main script:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-goal-append.ps1 `
  -Command review-preview `
  -Fixture `
  -Json
```

Supported commands:

- `status`
- `review-preview`
- `approve`
- `reject`
- `append-preview`
- `append-apply`
- `validate-candidate`
- `report`
- `safe-summary`

Default behavior is read-only fixture review-preview. Live mode is optional and
currently blocks safely when no append-step endpoint is available.

## Exact Confirmations

Approve requires:

```text
I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION
```

Append apply requires:

```text
I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION
```

Approve also requires a safe approval reason. Append apply requires a safe
append reason.

## Fixture Flow

Fixture mode is CI-safe and deterministic:

- campaign id: `goal-append-fixture-campaign-355`;
- generated goal id: `generated-goal-355-fixture`;
- candidate path: `.agent/tmp/goal-append/fixture/generated-goal-355-fixture.md`;
- appended step id: `appended-generated-goal-355-fixture-step`;
- appended step state: `pending`;
- goal budget before/after: `1 -> 0`.

Review preview creates no files. Approve writes review state and a reviewed copy
under ignored `.agent/tmp/goal-append`. Append preview creates no campaign
state. Append apply writes one metadata-only campaign-state record with
`task_created=false`, `task_claimed=false`, `execution_started=false`,
`worker_loop_started=false` and `token_printed=false`.

## Local Candidate Flow

Local candidate mode may review the MG354 generated file:

```text
.agent/tmp/generated-goals/local-codex/generated-goal-354-local-codex.md
```

The controller validates:

- candidate path is under an allowed repo-local review/generated-goal root;
- path traversal is absent;
- expected hash matches when supplied;
- metadata uses `skybridge.generated_goal_metadata.v1`;
- `human_review_required=true`;
- `import_allowed=false`;
- `execution_allowed=false`;
- `token_printed=false`;
- required safety sections are present.

Candidate paths outside allowed repo-local roots are blocked. Absolute paths are
accepted only when they resolve inside an allowed root.

## Live Metadata Flow

Live mode is metadata-only. The reserved live ids are:

- campaign id: `live-goal-append-campaign-355-001`;
- appended step id: `live-appended-generated-goal-step-355-001`.

If the deployed server does not yet expose an append-step endpoint, live append
returns `live_append_endpoint_missing`. It must not fake success. Fixture and
local metadata append remain the MG355 proof.

## Review State

Default state location:

```text
.agent/tmp/goal-append/review-state/review-state.json
```

The state records candidate hash, review state, approval or rejection reason,
timestamp and `token_printed=false`. It stores no raw prompts, no raw Codex
responses, no process streams, no tokens and no credentials.

Reviewed goal copies default to:

```text
.agent/tmp/goal-append/reviewed-goals/
```

Repository-local `goals/reviewed` remains review material only and is not an
execution queue.

## Goal Budget

Append preview and append apply require `GoalBudgetRemaining >= 1`. A successful
append decrements the budget by one. Budget exhaustion blocks append before any
campaign metadata write.

## Manual M5 Test

Fixture preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-goal-append-review-test.ps1 `
  -Fixture `
  -ReviewPreview `
  -Json `
  -WriteReport
```

Fixture approve:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-goal-append-review-test.ps1 `
  -Fixture `
  -Approve `
  -ApprovalReason "Operator approved fixture metadata review only." `
  -Confirm I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION `
  -Json `
  -WriteReport
```

Fixture append apply:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\manual-goal-append-review-test.ps1 `
  -Fixture `
  -AppendApply `
  -AppendReason "Operator appended fixture metadata only." `
  -Confirm I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION `
  -Json `
  -WriteReport
```

Checklist:

1. Review preview shows metadata valid and safety valid.
2. Approve records a reason and review state only.
3. Append preview proposes exactly one step.
4. Append apply writes exactly one non-executed step.
5. `task_created=false`.
6. `task_claimed=false`.
7. `execution_started=false`.
8. `worker_loop_started=false`.
9. `token_printed=false`.

## Reports

When `-WriteReport` is used:

- `.agent/tmp/goal-append/goal-append-review.md`
- `.agent/tmp/goal-append/goal-append-review.json`

Reports include safe path, SHA256 hash, review state, append state, budget
before/after, blockers, warnings and disabled-action flags. They exclude raw
prompts, raw responses, process streams, tokens, credentials, cookies, provider
headers, proxy profiles and complete environment listings.

## Failure Modes

The controller blocks instead of mutating when:

- candidate file is missing;
- candidate path is outside allowed roots;
- expected hash does not match;
- generated goal metadata is unsafe;
- required safety sections are missing;
- approve confirmation is missing;
- approval or append reason is missing;
- append confirmation is missing;
- review state is not approved;
- budget is exhausted;
- an appended step already exists;
- live append endpoint is unavailable.

## Next Milestone

MG356 adds the bounded goal budget loop. It may consume reviewed/appended
metadata, but it must still preserve one-step-at-a-time gates, explicit
confirmation, sanitized evidence and `token_printed=false`.

In MG356 the append bridge is only one possible bounded action. When selected,
it appends one already-reviewed candidate as metadata, consumes one budget unit,
leaves the new step pending, and stops without task creation or execution.
