# Sandbox Install Operator Acceptance

Sandbox install acceptance verifies that the portable package can be rehearsed locally without mutating the host OS.

Required checks:

- install plan and apply preview are safe;
- package applies only under `.agent/tmp/install-sandbox/current/`;
- sandbox contains `skybridge.ps1`, `skybridge.cmd`, launcher, local session, doctor and runbook docs;
- forbidden dependency, VCS, build, raw log and secret-like paths are absent;
- sandbox launcher status and start-preview run safely;
- doctor, demo and portable safe-summary run without worker execution;
- uninstall removes only `.agent/tmp/install-sandbox/current/`;
- upgrade and rollback write only under `.agent/tmp/install-sandbox/`;
- reports keep `token_printed=false`.

Disabled capabilities remain disabled: Codex worker, workunit creation/apply, task creation, task claim, task PR creation, generic queue apply, start-all, start-queue, resume apply, remote execution and arbitrary command dispatch.
