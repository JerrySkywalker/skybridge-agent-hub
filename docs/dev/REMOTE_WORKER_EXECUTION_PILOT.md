# Remote Worker Execution Pilot

## 2026-05-26 - remote-docs-exec-pilot-002

This low-risk docs-only pilot records a remote execution path for SkyBridge Agent Hub.

- Task ID: `remote-docs-exec-pilot-002`
- Worker target: `laptop-zenbookduo`
- Control plane path: cloud SkyBridge queued the task for a local edge worker.
- Claim/auth path: the local edge worker claimed the task through direct bearer-token auth.
- Execution path: Codex performed this documentation-only repository change.
- Validation/package path: the worker is expected to validate the result, package a child PR, run CI Guardian and report safe task evidence.
- Scope boundary: only `docs/dev/REMOTE_WORKER_EXECUTION_PILOT.md` was modified.
- Safety boundary: no secrets, `.env` files, production config, deployment credentials, GitHub settings or server root configuration were touched.
- Evidence boundary: raw command output and secrets are not uploaded to SkyBridge; only concise safe summaries should be reported.

Result: the pilot proves the end-to-end queue, claim, Codex execution and worker validation handoff can be exercised with a reviewable docs-only change.

Recovery update: child PR #57 initially hit a GitHub Actions checkout HTTP 403/account-suspended failure and the cloud task was marked failed with `ci_status=blocked_github_checkout_403`. The checks later recovered and passed, and PR #57 merged at `2026-05-26T13:02:48Z` with merge commit `99c4c21b2fb1881596d48db43482beedbb0384a8`.

Final proof: cloud control plane -> local worker claim -> Codex docs edit -> child PR -> GitHub Actions green -> merge is proven for this docs-only pilot.

## 2026-05-26 Reliability Follow-Up

Super Goal 168 adds the missing repair and operator workflow around this pilot:

- CI Guardian fixture classification distinguishes checkout HTTP 403, account-suspended text, transient checkout/fetch failures, real test/build failures, pending checks and green recovery.
- `skybridge-rerun-ci.ps1` provides a dry-run-first helper for one bounded rerun batch instead of indefinite retries.
- `/v1/tasks/:taskId/evidence-repair` appends a `task.evidence_repaired` event and updates EvidenceSummary with `recovered=true` and statuses such as `passed_after_rerun`, while preserving the original failed event.
- `skybridge-status.ps1` shows recovered evidence in compact task output and derives `display_status=recovered` for failed tasks whose EvidenceSummary has `recovered=true` and `ci_status=passed_after_rerun`.
- `skybridge-control.ps1` replaces manual project-control `Invoke-RestMethod` snippets for status/start/pause/stop/max-task changes.

Interpretation for `remote-docs-exec-pilot-002`: the initial failed task event remains historically accurate because CI was blocked at first. The later green checks and merged child PR should be recorded as recovered evidence rather than by deleting or rewriting the original failure.

## 2026-05-26 Operator Workflow Follow-Up

Super Goal 169 adds the CLI workflow that should replace handwritten task/control API calls:

- `skybridge-submit.ps1` creates one goal/task only with `-Apply`; default behavior is dry-run.
- `skybridge-run-once.ps1` captures status before/after, optionally submits a task, starts project control with `max_tasks=1`, register-heartbeats the worker, invokes the edge worker with `-PollOnce`, and restores project control to paused.
- `skybridge-hermes-cli.ps1` can route `goal submit`, `project status/start/pause`, `worker status/heartbeat`, and `loop run-once` to the dedicated operator helpers.

This is the bridge toward Hermes Web/CLI guided goal submission while keeping the worker execution path agent-agnostic.

## 2026-05-27 Operator Submit-And-Run Proof

The first real use of the v0.37 operator workflow created and executed task `operator-real-docs-task-170` without handwritten API calls:

- `skybridge-submit.ps1 -Apply` created the docs-only task.
- `skybridge-run-once.ps1 -NoSubmit -Apply` executed one `-PollOnce` worker pass and restored project control to paused.
- Child PR #60 passed GitHub Actions and merged through the low-risk child PR lifecycle policy.

The execution path is now proven from operator CLI submission through local worker execution and PR merge. After the cloud server was updated to the latest main image, the evidence repair endpoint accepted recovered evidence for `operator-real-docs-task-170`; raw status remains failed by design while compact status now presents the operator-facing task state as recovered.
