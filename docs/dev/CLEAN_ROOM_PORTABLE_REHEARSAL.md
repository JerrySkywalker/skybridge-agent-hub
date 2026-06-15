# Clean-room Portable Rehearsal

The clean-room rehearsal validates the portable package from an ignored local extraction root:

```text
.agent/tmp/portable-package/clean-room/skybridge-agent-hub-portable
```

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-portable-package.ps1 -Command clean-room-rehearsal
```

The rehearsal records only command id, sanitized command preview, exit code, duration, and safe JSON summary. It does not persist raw command transcripts, stdout, stderr, prompts, worker logs, CI logs, or environment dumps.

Disabled throughout:

- Codex worker execution;
- workunit apply;
- task claim;
- queue apply;
- remote execution;
- arbitrary command dispatch;
- registry, startup, scheduled task, service, and powercfg mutation.

`token_printed=false`.

