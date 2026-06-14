# Windows Launcher Preview

The Windows launcher preview reports planned launcher metadata only. It does not write registry keys, Startup folder entries, scheduled tasks, services, power configuration or sleep settings.

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command launcher-preview -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-windows-launcher-preview.ps1 -Command report -Json
```

Report paths:

- `.agent/tmp/windows-launcher-preview/windows-launcher-preview.json`
- `.agent/tmp/windows-launcher-preview/windows-launcher-preview.md`

token_printed=false
