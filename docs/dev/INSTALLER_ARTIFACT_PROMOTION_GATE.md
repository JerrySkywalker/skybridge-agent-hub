# Installer Artifact Promotion Gate

The installer artifact promotion gate is a sandbox-only preview for `v1.9.0-installer-promotion-rc`.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-installer-promotion.ps1 -Command promotion-gate -Json
```

The gate requires release workflow classification, tag safety classification, installer candidate validation, sandbox-installed runtime rehearsal, install/upgrade/rollback soak, recovery sandbox, operator acceptance v3, idle queue state, and disabled execution controls.

Reports are written under `.agent/tmp/release-candidate/`. No host install, network update, manual upload, or manual GitHub Release creation is allowed. `token_printed=false`.
