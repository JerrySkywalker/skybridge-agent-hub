# Host Mutation Permission Model

Host mutation is disabled by default for the installer promotion RC.

Disabled permissions:

- registry writes;
- startup folder writes;
- scheduled task creation;
- service installation;
- PATH mutation;
- power configuration mutation;
- Program Files installation;
- desktop shortcuts;
- Start Menu shortcuts.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-host-mutation-gate.ps1 -Command gate -Json
```

The gate emits preview metadata only and must not mutate host settings. `token_printed=false`.
