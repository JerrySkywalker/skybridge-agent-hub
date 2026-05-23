# Cloud Supervisor Runbook

This runbook validates SkyBridge against an existing cloud-hosted Hermes Agent through a local SSH tunnel. It does not expose Hermes publicly, deploy production changes, mutate GitHub settings or enable unattended auto-merge.

## SSH Tunnel

Start the operator-managed SSH tunnel that forwards a local loopback port to the private Hermes API. Keep it bound to localhost.

Example shape:

```powershell
ssh -N -L 127.0.0.1:18642:127.0.0.1:<remote-hermes-port> <server-alias>
```

Do not publish the Hermes API port directly to the internet.

## Local Env

Create the local Hermes env file outside Git:

```powershell
New-Item -ItemType Directory -Force "$HOME\.skybridge" | Out-Null
Copy-Item .\config\hermes.env.example.ps1 "$HOME\.skybridge\hermes.env.ps1"
```

Edit the local file with real values:

```powershell
$env:HERMES_API_BASE = "http://127.0.0.1:18642"
$env:HERMES_API_KEY = "<local key>"
$env:HERMES_MODEL = "<optional default model>"
```

Validate presence-only loading:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\load-hermes-env.ps1 -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-env-loading.ps1
```

## Server Key Alignment

The cloud Hermes server and local client must agree on the API key configured server-side, commonly as `API_SERVER_KEY` or the equivalent deployment variable. Keep the server-side value in the server secret store or private environment only.

Do not commit local or server key material, and do not paste it into PRs, issues, logs, docs or chat.

## Health Test

Dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-api.ps1 -DryRun -Json
```

Real local tunnel test:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-api.ps1 -Json
```

Expected connected endpoints include `/health`, `/health/detailed`, `/v1/capabilities` and optionally `/v1/models`.

## Run Submission Test

Dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-run.ps1 -DryRun -Json
```

Real harmless prompt:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-cloud-run.ps1 -Json
```

The script requests no tools and reports only redacted metadata.

## Supervisor Dry Run

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode Status `
  -UseHermesApi `
  -DryRun `
  -Json
```

Hermes health through the supervisor bridge:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode HermesHealth `
  -UseHermesApi `
  -Json
```

Hermes safe run smoke through the supervisor bridge:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode HermesRunSmoke `
  -UseHermesApi `
  -Json
```

## Phone Notification Test

Default dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -UseHermesApi `
  -Json
```

One explicit non-urgent phone send:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode NotifyTest `
  -UseHermesApi `
  -Send `
  -Json
```

Do not use urgent severity for connectivity smoke tests.

## Auto-Merge Sweep Dry Run

Supervisor mode:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-supervisor.ps1 `
  -Mode AutoMergeSweepDryRun `
  -UseHermesApi `
  -DryRun `
  -Json
```

Composed smoke:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-hermes-supervised-sweep.ps1 -DryRun -Json
```

Do not pass `-EnableAutoMerge` unless an operator intentionally wants a guarded real sweep for safe docs-only `ai/**` PRs.

## Safety Boundaries

- Do not print or commit `HERMES_API_KEY`.
- Do not commit `$HOME\.skybridge\hermes.env.ps1` or bootstrap notification env files.
- Do not expose Hermes publicly.
- Do not deploy to production from this workflow.
- Do not edit `/opt`, OpenResty, Authelia, 1Panel or Docker daemon configuration.
- Do not mutate GitHub settings or branch protection.
- Do not enable always-on unattended auto-merge.
- Keep default smokes dry-run or presence-only.

## Disable And Roll Back

1. Stop the SSH tunnel process.
2. Remove `HERMES_API_BASE` and `HERMES_API_KEY` from the current shell.
3. Move or delete `$HOME\.skybridge\hermes.env.ps1`.
4. Rotate the server-side Hermes API key if a local machine or shell is suspected compromised.
5. Re-run dry-run smokes to confirm scripts report `missing_base` or `missing_key` without exposing values.
