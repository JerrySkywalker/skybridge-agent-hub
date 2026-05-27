# Prepare SkyBridge Dogfood Self-Bootstrap Sprint

## Goal

Run the first bounded dogfood self-bootstrap sprint through `skybridge-supervise.ps1`: plan one safe proposal, convert it to one executable docs task, run it once through `laptop-zenbookduo`, package a child PR, and report evidence back to SkyBridge.

## Safety Bounds

- `MaxRounds=1`.
- Only one proposal may be converted.
- Only low-risk docs work may run.
- Worker execution must use `PollOnce`, not a long-running loop.
- Project control must return to `paused`.
- Token values and token file contents must not be printed.

## Preflight Result

Preflight against `https://skybridge.jerryskywalker.space` succeeded:

- project `skybridge-agent-hub` was paused;
- `laptop-zenbookduo` registered and heartbeated online through token-file auth;
- no queued or running tasks were visible;
- supervisor dry-run selected `proposal-d90d09da925d2cf0`;
- selected proposal was `Record master goal plan`;
- proposal risk was `low`;
- task type was `docs`;
- required capabilities included `codex`;
- expected files were docs-only:
  - `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`
  - `docs/dev/PROGRESS.md`;
- dry-run stop reason was `dry_run_preview_complete`.

## Apply Result

The real supervisor apply did not reach proposal conversion or worker execution. The structured failed supervisor run was:

- `supervisor_run_id`: `supervisor-run-20260527045305-6522d2e0a752`
- `status`: `failed`
- `stop_reason`: `supervisor_error`
- `current_round`: `1`

The cloud server returned `404 Not Found` for `POST /v1/master-goals`, which means the deployed cloud server image does not currently expose the planner persistence endpoint required by `skybridge-plan.ps1 -Apply`.

No executable task was created, no child PR was opened, and no worker `PollOnce` execution ran. Project control was checked after the failed apply and remained:

- `state=paused`
- `stop_requested=false`
- `stop_reason=operator_paused`

## Blocker

The first dogfood self-bootstrap sprint is blocked on cloud server deployment/version alignment. The local branch contains the supervisor UX and safety improvements, but the cloud server must expose the Super 172 planner persistence routes before a real supervisor apply can convert a proposal.

Required route family:

- `POST /v1/master-goals`
- `POST /v1/planning-sessions`
- `GET /v1/task-proposals`
- `POST /v1/task-proposals/:proposalId/convert`

After the cloud server is updated, rerun the same bounded apply command with `MaxRounds=1`.
