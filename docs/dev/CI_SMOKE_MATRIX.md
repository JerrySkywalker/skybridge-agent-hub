# CI Smoke Matrix

The smoke matrix groups bounded validation scripts so future goals can run focused checks instead of every smoke manually.

Groups:

- fast
- release
- bootstrap-complete
- control-plane
- resident
- pairing-approval
- trusted-docs
- failure-budget
- evidence-retention
- audit-redaction
- workunit-safe
- desktop
- web

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-smoke-matrix.ps1 -Command list
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-smoke-matrix.ps1 -Command run-fast
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-smoke-matrix.ps1 -Command run-bootstrap-complete
```

Smoke matrix reports persist safe metadata only and do not persist raw logs.

`token_printed=false`

