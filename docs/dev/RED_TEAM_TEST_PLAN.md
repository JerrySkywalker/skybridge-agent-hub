# Red-team Test Plan

Status: RC smoke pack.

The red-team pack exercises known dangerous inputs against preview-only local auth, installer, host mutation, attestation, SBOM, and tag safety contracts.

## Coverage Matrix

| Scenario | Smoke |
| --- | --- |
| Auth rejects authorization header persistence | `smoke-auth-gate-rejects-token-payload.ps1` |
| Auth rejects bearer-shaped payloads | `smoke-auth-gate-rejects-token-payload.ps1` |
| Auth rejects unsafe token status payloads | `smoke-auth-gate-rejects-token-payload.ps1` |
| Origin rejects non-loopback | `smoke-auth-origin-policy.ps1` |
| Command router rejects shell command text | `smoke-redteam-command-injection-rejected.ps1` |
| API rejects execution and queue apply requests | `smoke-redteam-command-injection-rejected.ps1` |
| Path traversal is rejected in package/install paths | `smoke-redteam-path-traversal-rejected.ps1` |
| Host mutation gate blocks registry/startup/service/scheduled-task/PATH/power settings | `smoke-redteam-host-mutation-blocked.ps1` |
| Installer interlock blocks real install | `smoke-redteam-host-mutation-blocked.ps1` |
| Release guard classifies tag side effects | `smoke-tag-safety-gate.ps1` |
| Attestation reports no private key | `smoke-attestation-no-private-key.ps1` |
| SBOM report excludes environment snapshots | `smoke-sbom-preview.ps1` |
| Token status remains false in generated reports | `smoke-v2-local-control-plane-token-printed-false.ps1` |

## Run Order

1. `smoke-redteam-command-injection-rejected.ps1`
2. `smoke-redteam-path-traversal-rejected.ps1`
3. `smoke-redteam-host-mutation-blocked.ps1`
4. `smoke-authenticated-session-rehearsal.ps1`
5. `smoke-auth-control-plane-soak.ps1`
6. `smoke-v2-local-control-plane-rc-report.ps1`
7. `smoke-v2-local-control-plane-token-printed-false.ps1`

## Stop Conditions

Stop the release candidate if any smoke accepts a command-shaped payload, persists raw auth values, reports raw logs, enables execution/apply, enables host mutation, or leaves tag workflow side effects unclassified.
