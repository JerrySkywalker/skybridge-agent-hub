# Local Onboarding Runbook

1. Verify bootstrap complete:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-complete.ps1 -Command gate
```

2. Generate product readiness and runtime reports:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-diagnostics.ps1 -Command report
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-runtime.ps1 -Command report
```

3. Review Web/Desktop first-run wizard panels.

4. Keep disabled:

- execution
- queue apply
- remote execution
- arbitrary command dispatch
- global trusted-docs auto-merge

token_printed=false
