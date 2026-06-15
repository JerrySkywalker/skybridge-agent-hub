# Security Threat Model: v2 Local Control-plane

Status: RC preview.

This model covers the v2 local auth control-plane release candidate. The release candidate is local, fixture-only, and preview-only. It does not graduate production identity, worker execution, remote execution, arbitrary command dispatch, or host mutation.

## Assets

- Local control-plane status metadata.
- Fixture-only local auth session records.
- Hash-only session store state.
- Local auth, attestation, SBOM, host consent, and release guard reports.
- Tag workflow side-effect classification.

## Trust Boundaries

- Browser or desktop UI to local preview APIs.
- Local preview APIs to session store.
- Control-plane preview routes to worker and approval fixtures.
- Installer preview to host mutation interlock.
- Tag creation to existing repository workflows.

## Threats And Controls

| Threat | Control | Validation |
| --- | --- | --- |
| Token leakage | Store hash-only fixture session records; reject token-like payloads in normal auth reports. | `smoke-auth-session-redaction.ps1`, `smoke-v2-local-control-plane-token-printed-false.ps1` |
| Authorization header persistence | Reject authorization header values from reports and session store. | `smoke-auth-gate-rejects-token-payload.ps1` |
| Raw log leakage | Rehearsal and soak persist safe summaries only. | `smoke-authenticated-session-rehearsal.ps1`, `smoke-auth-control-plane-soak.ps1` |
| Arbitrary command injection | Auth gate rejects command-shaped payloads and execution flags. | `smoke-redteam-command-injection-rejected.ps1` |
| Shell metacharacter injection | Command-shaped payloads remain rejected before execution surfaces. | `smoke-redteam-command-injection-rejected.ps1` |
| Path traversal | Installer/package path candidates outside safe relative paths are rejected in smoke coverage. | `smoke-redteam-path-traversal-rejected.ps1` |
| Unsafe origin | Loopback origin policy accepts localhost, 127.0.0.1, ::1, and repo-local fixtures only. | `smoke-auth-origin-policy.ps1` |
| Remote execution confusion | Remote execution remains disabled in auth, release, and queue gates. | `smoke-auth-does-not-enable-execution.ps1` |
| Host mutation confusion | Auth cannot enable host mutation; host consent remains blocked by default. | `smoke-redteam-host-mutation-blocked.ps1` |
| Installer consent misuse | Installer safety interlock blocks real install and host mutation permissions by default. | `smoke-redteam-host-mutation-blocked.ps1` |
| Workflow tag side effects | Release workflow guard classifies tag-triggered workflow side effects before tag creation. | `smoke-tag-safety-gate.ps1` |
| Artifact tampering | Attestation preview uses hash-only or fixture signatures and no production signing key. | `smoke-attestation-no-private-key.ps1` |
| Stale session or lock abuse | Active task, stale lease, runner lock, and session state checks remain explicit preflight gates. | release preflight and local auth session smokes |
| Queue apply bypass | Queue apply stays disabled; auth does not grant write scope. | `smoke-auth-does-not-enable-execution.ps1` |
| Worker execution bypass | Rehearsal, soak, and release gates keep worker execution disabled. | `smoke-authenticated-session-rehearsal.ps1` |

## Residual Risk

The RC does not prove a production identity provider, durable user sessions, or a real localhost server under load. Those are future goals and must preserve the same secret hygiene, disabled execution defaults, and host mutation interlocks.
