# Shared PowerShell Modules

Shared modules live under `scripts/powershell/lib/` and are the preferred implementation path for managed-mode, BOINC-like preview, resource-gate, finalizer, evidence, and smoke harness logic.

## Import Pattern

Compatibility wrappers import modules relative to `$PSScriptRoot`:

```powershell
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force
```

If an import fails, the wrapper exits before doing work. This is intentional fail-closed behavior.

## Helper Scripts

Some scripts remain parameterized helpers and are not standalone proof of execution safety. Use focused wrapper smokes instead of broad helper sweeps when validating a goal.

## Evidence

Evidence helpers accept safe paths under `.agent/tmp/**`, compute SHA-256 hashes, and reject raw artifact markers. Archive compression is not part of Goal 214.

## Reports

`scripts/powershell/skybridge-core-engine-report.ps1 -Command report -Json` writes:

- `.agent/tmp/core-engine/goal-214-core-engine-report.json`
- `.agent/tmp/core-engine/goal-214-core-engine-report.md`

Both files are ignored local artifacts and must keep `token_printed=false`.
