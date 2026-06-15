# v2 Local Control-plane Release Notes

Version: `v2.0.0-local-auth-control-plane-rc`

This release candidate completes the preview security layer for local control-plane access.

## Added

- Security threat model for the v2 local control-plane.
- Auth and host mutation threat model.
- Red-team smoke plan and required rejection smokes.
- Fixture-only authenticated local session rehearsal.
- Bounded auth/control-plane soak.
- v2 local control-plane RC report.
- v2 security hardening summary and roadmap.

## Safety Posture

- Auth remains fixture-only.
- Session state remains hash-only.
- Preview APIs expose safe metadata only.
- Host mutation remains disabled.
- Installer mutation remains blocked.
- Tag workflow side effects are classified before tag creation.
- Manual GitHub Release creation and manual artifact upload remain disabled.

## Validation

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-redteam-command-injection-rejected.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-redteam-path-traversal-rejected.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-redteam-host-mutation-blocked.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-authenticated-session-rehearsal.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-auth-control-plane-soak.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-v2-local-control-plane-rc-report.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-v2-local-control-plane-token-printed-false.ps1
```
