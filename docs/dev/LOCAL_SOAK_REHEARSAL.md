# Local Soak Rehearsal

The local soak script repeats safe fixture-only local session checks with bounded defaults.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-local-soak.ps1 -Command report
```

Defaults:

- max iterations: 3;
- max duration metadata: 120 seconds;
- fixture-only or short-lived non-worker paths;
- no worker execution;
- no workunit apply;
- no queue apply;
- no raw logs persisted;
- no background process left running;
- `token_printed=false`.

