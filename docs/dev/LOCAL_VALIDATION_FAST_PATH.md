# Local Validation Fast Path

Use this path for small docs, release and cockpit changes.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-bootstrap-complete-status.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-operator-cockpit.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-operator-cockpit.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-smoke-matrix-fast.ps1
```

For release closeout, run the bootstrap-complete group and repository validation before opening the PR.

`token_printed=false`

