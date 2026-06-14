# Failure Recovery Runbook V1

Failure recovery in v1 is classification and refusal first.

Rules:

- No silent rerun.
- No automatic retry.
- Retry requires explicit future operator authorization.
- Replacement requires a no-mutation classification.
- `pr_created_hold`, raw artifact detection, dirty worktree, disallowed path changes, secret detection, and `token_printed_true` block retry.
- Future replacement does not execute by itself.

Validate:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-failure-budget-no-silent-rerun.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-v1-release-requires-failure-budget.ps1
```
