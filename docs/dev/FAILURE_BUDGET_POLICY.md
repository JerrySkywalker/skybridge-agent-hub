# Failure Budget Policy

Goal 219 adds a safe failure budget model for the BOINC-like v1 release path. It is an infrastructure policy only; it does not execute Codex, create workunits, create tasks, claim tasks, create PRs, or retry anything.

## Contracts

- `skybridge.failure_budget.v1`
- `skybridge.failure_classification.v1`
- `skybridge.retry_authorization_gate.v1`
- `skybridge.replacement_authorization_gate.v1`
- `skybridge.failure_budget_report.v1`
- `skybridge.failure_budget_blocker.v1`

## Failure Classification

Failure classes distinguish no-mutation failures from unsafe states:

- `timeout_no_mutation` and `nonzero_no_mutation` may allow a future explicit replacement only after a new operator authorization.
- `timeout_with_changes`, `nonzero_with_changes`, `dirty_worktree`, `disallowed_path_change`, `pr_created_hold`, `raw_artifact_detected`, `secret_detected`, `unknown_unsafe`, and `token_printed_true` block retry.
- `pr_created_hold` moves through human review and finalizer, not retry.
- `resource_gate_blocked` and `repeated_blocker` are safe to summarize but do not authorize execution.

## Retry Rules

- `retry_requires_explicit_authorization=true`
- `replacement_requires_no_mutation_classification=true`
- `no_silent_rerun=true`
- `no_retry_after_pr_created=true`
- `no_retry_after_raw_artifact=true`
- `no_retry_after_disallowed_change=true`
- `no_retry_after_secret_detected=true`
- `token_printed=false`

The retry and replacement gates are decision records. They do not execute work and do not create new tasks. Future controlled execution must request a fresh operator approval and pass resource, evidence, audit, and human review gates.

## Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-failure-budget-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-failure-budget-no-silent-rerun.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-failure-budget-retry-requires-authorization.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-failure-budget-replacement-requires-no-mutation.ps1
```

