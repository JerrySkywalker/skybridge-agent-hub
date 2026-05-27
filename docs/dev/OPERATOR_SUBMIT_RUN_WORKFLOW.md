# Operator Submit-And-Run Workflow

## 2026-05-27 - operator-real-docs-task-170

This low-risk docs-only task records the first real operator submit-and-run workflow using the SkyBridge one-shot operator path.

- Task ID: `operator-real-docs-task-170`
- Project: `skybridge-agent-hub`
- Workflow path: an operator submitted one queued docs task, then invoked the one-shot run path instead of manually calling task and project-control APIs.
- Execution path: the local Codex worker handled the repository edit while the edge worker retained ownership of validation, commit, push and draft PR creation.
- Scope boundary: only `docs/dev/OPERATOR_SUBMIT_RUN_WORKFLOW.md` was modified by the task.
- Safety boundary: no secrets, `.env` files, production config, deployment credentials, GitHub settings or server root configuration were touched.
- Evidence boundary: raw command output and secrets are not uploaded to SkyBridge; only concise safe summaries should be reported.

Result: the submit-and-run operator flow has now been exercised by a real docs-only task with the expected ownership split between operator, worker and Codex execution.

## Final Outcome

- Submit command: `skybridge-submit.ps1 -Apply` created task `operator-real-docs-task-170` under goal `operator-real-goal-170` on the cloud SkyBridge server.
- Run command: `skybridge-run-once.ps1 -NoSubmit -Apply` started project control with `max_tasks=1`, register-heartbeated `laptop-zenbookduo`, invoked the edge worker with `-PollOnce`, and restored project control to `paused`.
- Child PR: https://github.com/JerrySkywalker/skybridge-agent-hub/pull/60
- CI status: AI branch validation, PR CI, Docker server and Docker web checks passed.
- Merge status: PR #60 was classified as a low-risk docs-only child task PR, marked ready, and merged by the existing lifecycle policy.
- Cloud task status: the task was initially marked `failed` because CI Guardian evaluated before pending GitHub checks had completed.
- Evidence repair: appending recovered evidence was attempted after PR #60 merged, but the cloud server returned 404 for `/v1/tasks/operator-real-docs-task-170/evidence-repair`; deploying the evidence-repair endpoint remains required before cloud task recovery can be reflected server-side.

Proof: operator submit -> run-once -> local worker claim -> Codex docs edit -> worker-owned child PR -> GitHub Actions green -> merge is proven. The remaining gap is cloud deployment of recovered-evidence repair support.
