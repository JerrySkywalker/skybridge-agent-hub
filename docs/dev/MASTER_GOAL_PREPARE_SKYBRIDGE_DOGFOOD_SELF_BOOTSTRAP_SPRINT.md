# Prepare SkyBridge Dogfood Self-Bootstrap Sprint

## Reviewed Plan

Run the first bounded dogfood self-bootstrap sprint through `skybridge-supervise.ps1`.
The sprint should prove the narrowest useful loop:

1. Plan one safe proposal for this repository.
2. Convert that proposal into one executable docs task.
3. Run that task once through `laptop-zenbookduo`.
4. Package the worker result as a child PR.
5. Report PR, CI and task evidence back to SkyBridge.

This is a dogfood validation of the planner, proposal conversion, edge worker,
child PR packaging and evidence reporting path. It is not a general unattended
execution rollout.

This document is the reviewed master goal plan record for the low-risk docs
proposal `proposal-d90d09da925d2cf0` / `task_proposal-d90d09da925d2cf0`.
It intentionally records the plan, safety limits, observed preflight/apply
results and current blocker without adding new executable work.

## Scope

- Project: `skybridge-agent-hub`
- Master goal: `master-goal-prepare-skybridge-dogfood-self-bootstrap-sprint`
- Selected proposal: `proposal-d90d09da925d2cf0`
- Selected task id: `task_proposal-d90d09da925d2cf0`
- Proposal title: `Record master goal plan`
- Risk: `low`
- Task type: `docs`
- Required capability: `codex`
- Dedupe key: `master-goal-prepare-skybridge-dogfood-self-bootstrap-sprint-record`

Expected files from the reviewed proposal:

- `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`
- `docs/dev/PROGRESS.md`

For this task execution, the focused required output is this master goal plan
document. Additional documentation updates should stay within the proposal's
docs-only file list.

## Safety Bounds

- `MaxRounds=1`.
- Convert at most one proposal.
- Run only low-risk docs work.
- Use `skybridge-run-once.ps1 -NoSubmit -Apply` for execution.
- Use `PollOnce`; do not start or leave a long-running worker loop.
- Restore project control to `paused` before stopping.
- Do not print token values or token file contents.
- Do not touch secrets, `.env` files, production config, deployment credentials,
  GitHub settings or server root configuration.
- Do not upload raw command output, raw Codex JSONL, patches, prompts or secrets
  to SkyBridge.
- For this documentation task, do not run `git add`, `git commit`, `git push`
  or `gh pr create`; the edge worker owns commit, push and draft PR creation
  after validation.

## Acceptance Criteria

- The plan summary is documented.
- Safety constraints and stop conditions are recorded.
- Changed files are docs-only.
- Validation command results are summarized.
- Any blocker is recorded with the route, command boundary or dependency that
  prevents completion.

## Planned Execution Flow

1. Preflight cloud state:
   - check `https://skybridge.example.com`;
   - confirm project control is paused;
   - confirm `laptop-zenbookduo` can heartbeat through token-file auth;
   - confirm no queued or running tasks would interfere.
2. Preview supervisor selection:
   - run the supervisor in dry-run mode;
   - verify it selects one low-risk docs proposal;
   - verify the generated run-once command uses the expected project, master
     goal, task and worker profile.
3. Apply the bounded supervisor:
   - create or reuse planner persistence records;
   - accept and convert only `proposal-d90d09da925d2cf0`;
   - start project control only for the bounded run;
   - run the worker once with `PollOnce`;
   - pause project control in `finally`.
4. Review worker output:
   - verify the child PR changes docs only;
   - verify CI status;
   - record task evidence and PR URL in SkyBridge;
   - treat recovered evidence as non-blocking when raw task history remains
     failed but evidence shows CI passed after repair.

## Stop Conditions

Stop the sprint immediately if any of these occur:

- no safe low-risk docs proposal is available;
- more than one proposal would be converted;
- the selected proposal expects non-docs files;
- worker auth, heartbeat or project control cannot be verified safely;
- cloud API routes required for planner persistence or proposal conversion are
  unavailable;
- child PR contents exceed the expected docs-only scope;
- CI is blocked by a real failure that is not an already-classified transient or
  recovered-evidence case;
- any step would require secrets, production config, GitHub settings, server
  root changes, force-push, or unattended auto-merge enablement.

## Preflight Result

Preflight against `https://skybridge.example.com` succeeded:

- project `skybridge-agent-hub` was paused;
- `laptop-zenbookduo` registered and heartbeated online through token-file auth;
- no queued or running tasks were visible;
- supervisor dry-run selected `proposal-d90d09da925d2cf0`;
- selected proposal was `Record master goal plan`;
- proposal risk was `low`;
- task type was `docs`;
- required capabilities included `codex`;
- expected files were docs-only;
- dry-run stop reason was `dry_run_preview_complete`.

The dry-run supervisor output showed it would run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
  -ApiBase "https://skybridge.example.com" `
  -ProjectId "skybridge-agent-hub" `
  -TaskId "task_proposal-d90d09da925d2cf0" `
  -GoalId "master-goal-prepare-skybridge-dogfood-self-bootstrap-sprint" `
  -NoSubmit `
  -Apply `
  -WorkerProfile "$HOME\.skybridge\worker.laptop-zenbookduo.json"
```

## Apply Result

The first real supervisor apply did not reach proposal conversion or worker
execution. The structured failed supervisor run was:

- `supervisor_run_id`: `supervisor-run-20260527045305-6522d2e0a752`
- `status`: `failed`
- `stop_reason`: `supervisor_error`
- `current_round`: `1`

The cloud server returned `404 Not Found` for `POST /v1/master-goals`, which
means the deployed cloud server image did not expose the planner persistence
endpoint required by `skybridge-plan.ps1 -Apply`.

No executable task was created, no child PR was opened, and no worker `PollOnce`
execution ran. Project control was checked after the failed apply and remained:

- `state=paused`
- `stop_requested=false`
- `stop_reason=operator_paused`

## Initial Blocker Resolved

The first real apply was blocked on cloud server deployment/version alignment.
The cloud server needed to expose the Super 172 planner persistence routes
before a real supervisor apply could convert a proposal.

Required route family:

- `POST /v1/master-goals`
- `POST /v1/planning-sessions`
- `GET /v1/task-proposals`
- `POST /v1/task-proposals/:proposalId/convert`

After the cloud server was updated, planner persistence succeeded and the
bounded retry reached proposal conversion and worker claim/start.

## Retry After Planner Persistence Deployment

The cloud server was later updated and `skybridge-plan.ps1 -Apply` successfully
persisted the master goal, planning session and task proposals. The retry
preflight confirmed:

- project control was `paused`;
- `laptop-zenbookduo` could register-heartbeat online through token-file auth;
- supervisor dry-run selected `proposal-d90d09da925d2cf0`;
- the selected task id would be `task_proposal-d90d09da925d2cf0`;
- the expected files remained limited to `docs/dev`.

During the retry, two local supervisor/worker reliability gaps were fixed before
the real apply:

- the worker compatibility check now honors persisted `task_type=docs` instead
  of inferring `code` from neutral task text;
- `skybridge-run-once.ps1` now passes the requested task id into
  `skybridge-edge-worker.ps1` and fails if PollOnce does not process that exact
  task.

The bounded retry apply ran as:

- `supervisor_run_id`: `supervisor-run-20260527051547-c11fd86e34b0`
- selected proposal: `proposal-d90d09da925d2cf0`
- converted task: `task_proposal-d90d09da925d2cf0`
- worker: `laptop-zenbookduo`
- mode: `apply`
- `MaxRounds`: `1`

The worker successfully claimed and started the converted task. Codex edited
`docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`, but
the Codex execution exited nonzero after repeated ChatGPT Codex websocket TLS
handshake EOF errors. The task was marked failed by the worker with
`error_summary=Codex exec failed or timed out.`

Final observed state for the retry:

- child PR URL: none;
- CI status: none;
- merge status: none;
- cloud task status: `failed`;
- evidence summary: none;
- project control: `paused`;
- stop reason: `task_failed`.

This proves the cloud planner persistence -> proposal conversion -> targeted
worker claim/start -> paused rollback path, but it does not yet prove the full
dogfood self-bootstrap sprint because Codex execution transport failed before
worker-owned child PR packaging.

## Current Blocker

The remaining blocker is Codex execution transport reliability. The worker-owned
Codex run changed a docs-only file but exited nonzero after repeated
`wss://chatgpt.com/backend-api/codex/responses` TLS handshake EOF errors. No
child PR, CI run, merge or recovered evidence exists for
`task_proposal-d90d09da925d2cf0`.

## Codex Transport Recovery Retry

The follow-up retry added bounded Codex transport recovery before re-running the
dogfood task:

- websocket, TLS handshake, EOF, connection reset and transport-error messages
  are classified as Codex transport failures;
- classified transport failures are retriable;
- the worker retries Codex execution at most once by default;
- retry failure evidence records `execution_error_class`, `retry_count` and
  `recovered=false`;
- non-transport execution, validation, build or CI failures are not classified
  as Codex transport failures.

The cloud preflight before retry confirmed:

- project control was `paused`;
- no queued or running tasks were visible;
- `task_proposal-59a0236fb69800cd` remained `blocked`;
- `task_proposal-d90d09da925d2cf0` was the only targeted failed task;
- `laptop-zenbookduo` could register-heartbeat through token-file auth.

The targeted retry requeued only `task_proposal-d90d09da925d2cf0` and ran
`skybridge-run-once.ps1 -NoSubmit -Apply` against that task id. Codex succeeded
on the first attempt in this retry, so the real run used `retry_count=0`; local
smoke coverage separately proved the one-retry path with `retry_count=1` and
`execution_error_class=codex_transport_eof`.

## Recovered Sprint Result

The bounded retry completed the first dogfood self-bootstrap sprint through the
recovered-evidence path:

- target task: `task_proposal-d90d09da925d2cf0`;
- selected proposal: `proposal-d90d09da925d2cf0`;
- worker: `laptop-zenbookduo`;
- child PR: `https://github.com/JerrySkywalker/skybridge-agent-hub/pull/69`;
- changed file: `docs/dev/MASTER_GOAL_PREPARE_SKYBRIDGE_DOGFOOD_SELF_BOOTSTRAP_SPRINT.md`;
- CI status: all required GitHub Actions checks passed;
- merge status: PR #69 merged by lifecycle policy;
- merge commit: `81399f6afff508b47f53ccaeeba4fbad8cfe6305`;
- project control final state: `paused`.

The task raw status remains `failed` by design because the original Codex
transport failure is preserved in task history. Evidence repair appended the
recovered result:

- `evidence_summary.recovered=true`;
- `ci_status=passed_after_pending`;
- `recovery_status=merged_after_pending_checks`;
- `risk_status=low_docs_only`;
- `validation_status=passed`.

This proves the bounded cloud planning -> proposal conversion -> targeted local
worker claim/start -> Codex docs edit -> child PR -> GitHub Actions green ->
policy merge -> recovered evidence loop. It does not enable long-running worker
loops; the next step should still be bounded multi-round supervision or planner
activation behind explicit operator gates.

## Evidence To Record After Codex Transport Recovers

- Supervisor run id, mode, status and stop reason.
- Selected proposal id and converted task id.
- Worker id and one-shot execution result.
- Child PR URL and changed-file summary.
- CI classification.
- Task evidence summary, including recovered-evidence status when applicable.
- Final project control state, expected to be `paused`.
