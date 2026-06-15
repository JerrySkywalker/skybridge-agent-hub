# Local Session Troubleshooting

If start preview reports a port conflict, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-doctor.ps1 -Command ports
```

The doctor explains the conflict but does not kill the owning process.

If stale metadata is suspected, run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command locks
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-session.ps1 -Command cleanup
```

Use `-Command stop` only for this local session metadata. Do not run queue, worker or workunit recovery commands for this manual local session. token_printed=false
