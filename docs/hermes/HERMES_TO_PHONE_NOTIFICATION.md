# Hermes To Phone Notification

Hermes-supervised phone notification uses the bootstrap notifier directly. It does not require the SkyBridge server or Notification Center.

Dry-run validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -UseHermesApi `
  -Json
```

Real non-urgent phone test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -UseHermesApi `
  -Send `
  -Json
```

The command sends exactly one `info` severity bootstrap notification when `-Send` is explicit. Default CI and smoke commands must omit `-Send`; they should use dry-run behavior only.

Safety notes:

- Do not send urgent notifications for connectivity smoke tests.
- Do not print or commit `HERMES_API_KEY` or bootstrap ntfy credentials.
- Do not depend on SkyBridge Notification Center for this path.
- Keep local config in `$HOME\.skybridge\hermes.env.ps1` and `$HOME\.skybridge\bootstrap-notify.env.ps1`.
