# Local Session Health Doctor

`skybridge-local-doctor.ps1` checks:

- repo cleanliness;
- bootstrap-complete gate;
- local productization RC status;
- local config validation and redaction;
- port availability for Web and server previews;
- stale lock and PID absence;
- required local commands;
- optional Cargo availability for Desktop checks;
- execution flags remaining disabled.

Commands:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command check
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command explain
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command cleanup-preview
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command report
```

The doctor never kills arbitrary processes and never enables execution. token_printed=false
