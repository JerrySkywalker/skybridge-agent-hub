# Offline Update Rollback Preview

The offline update and rollback preview stages candidate metadata for a sandbox version transition only.

It records:

- current sandbox version;
- candidate artifact version;
- staged update preview;
- rollback plan;
- no network update;
- no host mutation;
- no external writes.

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-channel-manifest.ps1 -Command offline-update-plan -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-channel-manifest.ps1 -Command rollback-plan -Json
```

`token_printed=false`.
