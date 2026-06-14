# BOINC-like v1 Controlled Release

BOINC-like v1 controlled release means SkyBridge has the telemetry, release gate, approval preview, failure budget, evidence retention, audit, Desktop, and Web surfaces needed to supervise future one-workunit trials. It does not mean unattended execution is enabled.

Implemented:

- Core engine and BOINC-like alpha evidence from Goals 214-216.
- Desktop resident worker preview shell from Goal 217.
- Server control plane, pairing preview, heartbeat ingest, and approval preview from Goal 218.
- Failure budget, evidence hash chain, audit trail, redaction scan, and safe export gate from Goal 219.
- Final release gate, release approval preview, release reports, release tag plan, and post-release smokes from Goal 220.

Still disabled:

- Codex worker execution.
- Workunit creation.
- Task creation and task claim.
- Generic bounded queue apply.
- Remote execution.
- Arbitrary command dispatch.
- Task PR auto-merge.

`token_printed=false` is an invariant for release reports, smokes, fixtures, UI, and docs examples.

Validate:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-release.ps1 -Command gate
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-v1-release-readiness-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-boinc-v1-release-token-printed-false.ps1
```
