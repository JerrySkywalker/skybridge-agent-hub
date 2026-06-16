# Authenticated Loopback API Hardening

Status: live-local preview.

The authenticated loopback API rehearsal exposes safe metadata routes only:

- `/status`
- `/readiness`
- `/metadata`

## Controls

- Loopback-only bind address.
- Loopback-only origin policy.
- Fixture hash header for authenticated metadata reads.
- Authorization header values are rejected.
- Cookies are not used.
- Private keys are not used.
- Raw auth values are not persisted.
- Command-shaped payloads are rejected.
- Execution/apply/start/claim routes are absent.

## Disabled Capabilities

- worker execution
- workunit apply
- task claim
- queue apply
- remote execution
- arbitrary command dispatch
- host mutation

## Validation

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-live-local-auth-request.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-live-local-rejects-remote-origin.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-live-local-rejects-command-text.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-live-local-no-worker-execution.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-live-local-no-queue-apply.ps1
```
