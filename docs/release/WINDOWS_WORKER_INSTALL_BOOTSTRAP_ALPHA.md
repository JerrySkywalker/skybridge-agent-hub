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

Install and repair are preview-only in MG325. MG330 adds exact-confirmed local
apply for a non-admin user-level heartbeat-only wrapper and a heartbeat pairing
drill. Apply remains local and bounded; it does not start task execution.

MG326 adds a separate Desktop Chat-to-Task panel. MG327 adds a separate Desktop
Task Templates panel. MG328 adds reviewed queued-record submit. MG329 adds a
separate Worker Runner Preview panel and PowerShell-only one-task fixture
runner for `safe-local-smoke.v1`. MG330 keeps worker service install/repair and
heartbeat pairing separate from runner apply.

## Worker Service Meaning

In Bootstrap Alpha, the worker service means a local Windows user-level
heartbeat-only wrapper that can later host a reviewed SkyBridge worker loop.
MG330 uses a non-admin local wrapper and safe metadata under
`$HOME\.skybridge\state`; it does not require admin Windows service install.
If a true Windows service is needed later, that path must report
`admin_required=true` and go through a future reviewed goal.

MG329 does not start the Windows service wrapper or worker loop. Its
`skybridge-worker-template-runner.ps1` helper can apply one safe local fixture
task only when pointed at the intended API base and given exact confirmation.
MG330 does not call that runner during install or heartbeat pairing.

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
$HOME\.skybridge\state\worker-service.json
```

The status and doctor scripts inspect presence and safe key names only. They do
not dot-source these files and do not print token values.

`skybridge.env.ps1` is expected to contain `SKYBRIDGE_API_BASE`.
`worker.env.ps1` is expected to contain `SKYBRIDGE_WORKER_ID`,
`SKYBRIDGE_REPO_ROOT`, and `SKYBRIDGE_WORKER_SERVICE_NAME`. The token file is
read only for authenticated heartbeat pairing; its value is never printed.

## Manual Status And Doctor

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-status.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-doctor.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-install-preview.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-repair-preview.ps1 -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-install.ps1 -Command preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-repair.ps1 -Command repair-preview -Json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-heartbeat-pairing-drill.ps1 -Command heartbeat-preview -Json
```

The main status schema is `skybridge.local_worker_service_status.v1`.

## Exact Confirmation Apply

Install apply:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-install.ps1 -Command apply -Confirm -ConfirmationText I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION -Json
```

Repair apply:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service-repair.ps1 -Command repair-apply -Confirm -ConfirmationText I_UNDERSTAND_REPAIR_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION -Json
```

Heartbeat pairing apply:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-heartbeat-pairing-drill.ps1 -Command heartbeat-apply -Confirm -ConfirmationText I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM -Json
```

These commands are exact-confirmed because they mutate local config/state or
register and heartbeat the worker. They do not claim tasks, start the worker
template runner, start a loop, run Codex, run MATLAB, create PRs, send
notifications, requeue tasks, unpause project control, or alter cloud deploy
infrastructure.

## Heartbeat Pairing Drill

The heartbeat drill uses the configured API base and worker token file to call:

- `POST /v1/workers/register`
- `POST /v1/workers/:workerId/heartbeat`
- `GET /v1/workers/:workerId`

The drill reports the worker id, redacted API host, registration status,
online/offline status, and last heartbeat time. It does not call task claim,
task start, task complete, task fail, campaign execution, or runner endpoints.

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

MG330 keeps these fields false:

- `claim_enabled=false`
- `execute_enabled=false`
- `template_runner_enabled=false`
- `worker_loop_started=false`
- `claim_created=false`
- `execution_started=false`
- `codex_run_called=false`
- `matlab_run_called=false`
- `arbitrary_shell_enabled=false`
- `notification_sent=false`
- `token_printed=false`

MG329 keeps Codex execution, MATLAB execution, arbitrary shell, worker loop,
unbounded run, project-control unpause, PR creation, and live cloud task claim
disabled.

Do not paste secrets, tokens, cookies, provider headers, raw prompts, stdout,
stderr, or full environment listings into docs, issues, logs, or screenshots.
