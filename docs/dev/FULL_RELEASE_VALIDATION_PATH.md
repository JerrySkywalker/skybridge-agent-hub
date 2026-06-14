# Full Release Validation Path

Use this path before a bootstrap-complete release tag.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-bootstrap-complete-gate.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-self-bootstrap-release-report.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-operator-cockpit.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-smoke-matrix-bootstrap-complete.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-bootstrap-complete-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\validate-powershell.ps1
corepack pnpm check
corepack pnpm -C apps/desktop build
```

If available, finish with `just check`.

Do not persist raw command output in release reports.

`token_printed=false`
