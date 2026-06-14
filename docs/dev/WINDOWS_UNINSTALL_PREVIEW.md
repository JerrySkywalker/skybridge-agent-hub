# Windows Uninstall Preview

Uninstall preview is metadata-only. It lists future cleanup concepts without removing files, services, scheduled tasks, registry entries or Startup entries.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command uninstall-preview -Json
```

Do not delete user data by default. Safe operator cleanup should only remove generated `.agent/tmp` metadata after review.

token_printed=false
