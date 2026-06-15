# Stability Cleanup Hardening

The stability cleanup hardening report collects safe cleanup previews for sandbox and fixture workflows.

It includes:

- stale sandbox cleanup preview;
- orphan fixture process detection;
- local session lock consistency check;
- sandbox size preview;
- repeated rehearsal stability summary.

Command:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-soak.ps1 -Command stability-cleanup
```

The command does not delete outside `.agent/tmp/install-sandbox/`, does not kill arbitrary processes and does not persist raw logs. `token_printed=false`.

Reports:

- `.agent/tmp/local-session/stability-cleanup-report.json`
- `.agent/tmp/local-session/stability-cleanup-report.md`
