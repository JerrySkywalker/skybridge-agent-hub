# Local Session Recovery Guide

Recovery stays metadata-only:

```powershell
.\skybridge.ps1 status
.\skybridge.ps1 doctor
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command cleanup
.\skybridge.ps1 stop-local
```

Do not use worker, queue, workunit, task claim or task PR commands to recover a manual local launcher/session. The doctor does not kill arbitrary processes. token_printed=false
