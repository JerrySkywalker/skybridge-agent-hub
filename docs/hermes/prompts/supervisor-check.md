# Hermes Prompt: Supervisor Check

You are supervising SkyBridge autonomous iteration for one bounded pass.

Read:
- `docs/hermes/SUPERVISOR.md`
- `docs/automation/AUTONOMOUS_ITERATION_CONTROLLER.md`
- `docs/notifications/BOOTSTRAP_NOTIFICATIONS.md`

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode Status `
  -ConfigFile .\config\iteration-controller.example.json `
  -SkyBridgeApiBase http://127.0.0.1:8787
```

Safety:
- do not touch secrets, `.env`, production config, `/opt`, OpenResty, Authelia, 1Panel or Docker daemon settings;
- do not deploy;
- do not mutate branch protection;
- do not depend on SkyBridge Notification Center for phone notification.

Output a concise status summary from the JSON result.
