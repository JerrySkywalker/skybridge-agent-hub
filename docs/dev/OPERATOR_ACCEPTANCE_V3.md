# Operator Acceptance v3

Operator acceptance v3 combines the release guard, sandboxed installer candidate, sandbox-installed runtime rehearsal, extended install soak, recovery sandbox, cleanup hardening, and Web/Desktop read-only panels.

Generate the report:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-operator-acceptance.ps1 -Command v3-report -Json
```

Reports:

- `.agent/tmp/operator-acceptance/operator-acceptance-v3-report.json`
- `.agent/tmp/operator-acceptance/operator-acceptance-v3-report.md`

Acceptance v3 does not enable worker execution, workunit apply, task claim, queue apply, host install, uploads, or manual GitHub Release creation.

`token_printed=false`
