# Hermes Health Watchdog

`scripts/powershell/watch-hermes-health.ps1` checks the local Hermes supervision path without exposing secrets.

It validates:

- local tunnel port availability when `HERMES_API_BASE` points at localhost;
- Hermes `/health`;
- Hermes `/v1/capabilities`;
- presence of `HERMES_API_KEY` without printing it.

## One-Shot Check

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 -Once
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 -Once -Json
```

The default mode is one-shot and no-send. Degraded states are reported as structured output so scheduled wrappers can decide how to continue.

## Loop Mode

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 `
  -Loop `
  -IntervalSeconds 60 `
  -MaxFailures 3
```

## Optional Phone Warning

Send one non-urgent bootstrap warning only after explicit opt-in:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\watch-hermes-health.ps1 `
  -Loop `
  -IntervalSeconds 60 `
  -MaxFailures 3 `
  -SendOnFailure
```

The warning uses `notify-bootstrap.ps1` with `warning` severity. It does not use urgent notifications for ordinary tunnel or API loss.

## Smoke

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-watch-hermes-health.ps1
```

The smoke runs a one-shot JSON check and does not send notifications.
