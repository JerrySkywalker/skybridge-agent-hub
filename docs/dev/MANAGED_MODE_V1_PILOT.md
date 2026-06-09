# Managed Mode v1 Pilot

Managed Mode v1 is the BOINC-like direction for SkyBridge Agent Hub, but Goal 208 keeps it in pilot-only form. General bounded queue apply remains disabled. The only authorized apply shape is one explicitly bounded pilot workunit under `managed-mode-pilot-208`.

## Distinction

General managed mode means the queue could select and execute multiple workunits over time. That is still disabled because locking, conflict handling, retry policy and operator review boundaries are not complete enough for unattended queue continuation.

Pilot mode is a narrow readiness and apply contract for one low-risk docs/local-smoke workunit. It proves the queue, scheduler and sanitized executor boundary can be joined without exposing broad execution controls.

## Pilot Limits

- `pilot_id=managed-mode-pilot-208`
- `mode=managed_mode_v1_pilot`
- `max_workunits=1`
- `max_tasks=1`
- `max_claims=1`
- `max_codex_executions=1`
- `max_prs=1`
- `max_runtime_minutes<=30`
- `max_parallel_per_repo=1`
- `stop_on_pr_created=true`
- `stop_on_ci_failure=true`
- `stop_on_warning=true`
- `require_human_review=true`
- allowed task types: `docs`, `local-smoke`, `docs/local-smoke`
- allowed paths: `README.md`, `docs/**`

Blocked surfaces include production deploy, secret rotation, server-root config, DNS, OpenResty config, Hermes config, GitHub settings, branch protection, arbitrary shell execution, auto execution and auto merge.

## Operator Review Boundary

The pilot may create at most one task PR. That PR must remain open for human review. The pilot must stop immediately after PR creation or controlled failure and must not continue to another workunit.

Goal 208C finalization is separate and may complete only after the human operator manually merges the task PR.

## Validation

Preview and readiness commands are read-only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command schema -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command readiness -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command plan-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command apply-gate -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-pilot.ps1 -Command pilot-preview -Json
```

Focused smokes:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-readiness-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-general-apply-disabled.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-policy-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-preview-no-mutation.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-one-workunit-only.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-docs-only.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-production.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-secrets.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-pilot-gate-rejects-auto-merge.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-no-start-all.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-no-unbounded-queue.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v1-token-printed-false.ps1
```

Every JSON result must keep `token_printed=false` and must not persist raw prompts, transcripts, stdout, stderr, raw worker logs or secrets.
