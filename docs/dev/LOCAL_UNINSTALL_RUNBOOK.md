# Local Uninstall Runbook

Current uninstall is a local preview only because productized install is not applied by default.

Safe cleanup:

- stop local dev servers you started manually
- delete generated `.agent/tmp` productization reports after review
- remove local build output if desired

Do not mutate:

- Windows registry
- Startup folder
- scheduled tasks
- services
- `powercfg`
- sleep or Modern Standby settings

Preview future cleanup metadata:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command uninstall-preview -Json
```

token_printed=false
