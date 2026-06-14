# Windows Autostart Preview

Autostart support is preview-only. The preview may describe shortcut, Startup entry, scheduled task and service metadata, but it must not apply host changes.

Strict defaults:

- `dry_run=true`
- `registry_mutation=false`
- `startup_folder_write=false`
- `scheduled_task_creation=false`
- `service_creation=false`
- `powercfg_mutation=false`
- `sleep_or_standby_mutation=false`
- `token_printed=false`

Use:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command startup-entry-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command scheduled-task-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command service-preview -Json
```
