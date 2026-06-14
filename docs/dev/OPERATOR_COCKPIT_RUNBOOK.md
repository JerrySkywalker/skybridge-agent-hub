# Operator Cockpit Runbook

The operator cockpit is read-only. It summarizes release status, bootstrap-complete status, active/stale/lock state, pairing, approval, resident polling, resource gate, queue/apply disabled state, completed runs, evidence retention, audit/redaction, trusted-docs scoped merge, blocked capabilities and the next safe action.

## Daily Check

1. Run the bootstrap-complete gate.
2. Confirm `active_tasks=0`, `stale_leases=0`, `runner_lock=none`.
3. Confirm remote execution, arbitrary command dispatch, execution and queue apply are disabled.
4. Confirm no open task PR exists.
5. Review the operator cockpit panels in Web and Desktop.
6. Use the smoke matrix fast path before any release/docs/infrastructure PR.

The cockpit must not add enabled execute, apply, start or claim buttons.

`token_printed=false`

