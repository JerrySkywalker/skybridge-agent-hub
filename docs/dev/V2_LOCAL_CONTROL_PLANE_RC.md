# v2 Local Control-plane RC

Status: release candidate preview.

The v2 local control-plane RC combines the local loopback auth model, hash-only fixture session store, API auth gate, read-only Web/Desktop auth surfaces, attestation preview, SBOM preview, host mutation consent preview, installer interlock, threat model, red-team pack, authenticated rehearsal, and bounded auth soak.

## Included

- Local loopback auth preview.
- Hash-only fixture session store.
- Safe metadata auth gate for local preview/control-plane fixtures.
- Read-only auth state panels in Web and Desktop.
- Signed manifest and attestation preview without production key material.
- SBOM and dependency inventory preview without network or uploads.
- Host mutation consent preview blocked by default.
- Installer safety interlock blocked by default.
- Threat model and red-team smoke pack.
- Authenticated local session rehearsal.
- Auth/control-plane soak with five default iterations.
- Tag workflow side-effect guard.

## Excluded

- Production identity.
- Real installer mutation.
- Host mutation.
- Worker execution.
- Workunit apply.
- Queue apply.
- Remote execution.
- Arbitrary command dispatch.
- Manual GitHub Release creation.
- Manual artifact upload.

## Evidence

- `.agent/tmp/local-auth/v2-local-control-plane-rc-report.json`
- `.agent/tmp/local-auth/v2-local-control-plane-rc-report.md`
- `.agent/tmp/local-auth/authenticated-session-rehearsal-report.json`
- `.agent/tmp/local-auth/auth-soak-report.json`
- `.agent/tmp/release-guard/tag-safety-gate.json`
