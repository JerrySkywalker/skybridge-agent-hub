# Tray Pause, Drain, and Emergency Controls

Desktop tray controls are preview-only in Goal 217. The tray state exposes:

- Open SkyBridge
- Worker Status
- Resource Gate
- Pause Preview
- Drain Preview
- Emergency Stop Preview
- Open Evidence Folder
- Open Logs Folder
- Quit

Pause, drain, and emergency stop preview commands may write only ignored safe state under `.agent/tmp/local-supervisor/`. They do not start or stop workers, kill processes, claim tasks, create tasks, execute Codex, run queue apply, mutate Docker, mutate GitHub, mutate resource policy, require admin privileges, alter registry, alter powercfg, or change sleep settings.

Preview holds are reversible with:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-supervisor.ps1 -Command clear-preview-holds -Json
```

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-desktop-tray-actions-preview-only.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-pause-preview-only.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-drain-preview-only.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-emergency-stop-preview-only.ps1
```
