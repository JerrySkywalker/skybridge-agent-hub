# Windows Worker Install Bootstrap Alpha

Bootstrap Alpha makes SkyBridge Desktop the local operator entry point for
inspecting and previewing local Windows worker service setup. This layer reports
installability, repairability, tool capabilities, and blockers. It does not
start task execution.

## What The Manager Does

- Reads local worker service status through
  `scripts/powershell/skybridge-worker-service-status.ps1`.
- Previews install actions through
  `scripts/powershell/skybridge-worker-service-install-preview.ps1`.
- Previews repair actions through
  `scripts/powershell/skybridge-worker-service-repair-preview.ps1`.
- Runs a read-only doctor through
  `scripts/powershell/skybridge-worker-service-doctor.ps1`.
- Shows the same safe fields in the Desktop Bootstrap Alpha Worker Setup panel.

Install and repair are preview-only in MG325. Apply is future work and must keep
exact confirmation, local user-level scope, and the no-execution boundary.

MG326 adds a separate Desktop Chat-to-Task panel. MG327 adds a separate Desktop
Task Templates panel. These panels may reference local tool capabilities from
worker setup, but they still produce or display previews only and do not start
the worker service, claim tasks, execute Codex, or execute MATLAB.

## Worker Service Meaning

In Bootstrap Alpha, the worker service means a local Windows service wrapper
that can later host a reviewed SkyBridge worker loop. MG325 only checks whether
that wrapper can be installed or repaired. It does not claim server tasks, run
Codex, run MATLAB, send notifications, or start a worker loop.

## Required Local Tools

- PowerShell 7+
- Git
- GitHub CLI (`gh`) for future PR/evidence workflows
- Node.js
- pnpm through Corepack
- Codex CLI for future Codex task templates
- MATLAB for future MATLAB experiment templates

Missing Codex or MATLAB is a capability warning in MG325, not a false pass.

## Local Config Locations

Expected local files are under the operator home directory:

```text
$HOME\.skybridge\skybridge.env.ps1
$HOME\.skybridge\worker.env.ps1
$HOME\.skybridge\worker-token.txt
```

The status and doctor scripts inspect presence and safe key names only. They do
not dot-source these files and do not print token values.

## Manual Status And Doctor

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-status.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-doctor.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-install-preview.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-repair-preview.ps1 -Json
```

The main status schema is `skybridge.local_worker_service_status.v1`.

## Interpreting Blockers

- `service_not_installed`: run the install preview and review planned local
  user-level service wrapper steps.
- `api_base_not_configured`: add safe API base config to
  `$HOME\.skybridge\skybridge.env.ps1`.
- `worker_token_file_missing`: create the local token file outside the repo.
- `repo_root_not_detected`: run the scripts from the SkyBridge Agent Hub repo or
  pass the intended repo root.
- `tool_missing_*`: install the required local tool before future worker
  execution goals.

Warnings identify degraded capabilities, such as missing `gh`, Codex, or MATLAB.

## Still Disabled

MG325 keeps these fields false:

- `claim_enabled=false`
- `execute_enabled=false`
- `worker_loop_started=false`
- `task_claimed=false`
- `codex_executed=false`
- `matlab_executed=false`
- `notification_sent=false`
- `token_printed=false`

Do not paste secrets, tokens, cookies, provider headers, raw prompts, stdout,
stderr, or full environment listings into docs, issues, logs, or screenshots.
