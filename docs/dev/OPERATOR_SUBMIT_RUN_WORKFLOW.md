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
