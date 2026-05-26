# Edge Worker Runbook

The edge worker is a local Windows PowerShell runtime that joins SkyBridge Worker Pool and executes one queued task at a time. It defaults to safe preview behavior unless you run a real `-PollOnce` without `-DryRun` or `-ClaimOnly`.

## Prepare Config

Copy an example to the gitignored local path:

```powershell
Copy-Item .\config\edge-worker.homepc.example.json .\config\edge-worker.json
```

Edit only local values such as `worker_id`, `repo_path`, `api_base`, `allowed_task_types` and validation commands. Do not add secrets to the config.

## Start Worker

Start SkyBridge API:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
```

Register and heartbeat:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Register `
  -Heartbeat `
  -Json
```

Preview the next claim:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -PollOnce `
  -DryRun `
  -Json
```

Claim without execution for local smoke testing:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -PollOnce `
  -ClaimOnly `
  -Json
```

Run one real task:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -PollOnce `
  -Json
```

Loop mode:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Loop `
  -Json
```

Stop loop mode with `Ctrl+C`.

## Recovery After Sleep

After the machine sleeps or loses network:

1. Run `-Heartbeat` to refresh worker status.
2. Inspect Worker Pool and Task Queue in the Operator Console.
3. If a task remains `claimed` or `running`, inspect `.agent/workers/<worker>/<task>/`.
4. Fail or requeue the task through the API only after checking local state.
5. Resume with `-PollOnce -DryRun` before running real execution.

## Safety Boundaries

- Do not run real tasks from a dirty implementation branch unless that is the task branch.
- Do not commit `.agent`, `.data`, `.env`, local worker config or secret-like files.
- Do not run production deployment or server-root commands through worker tasks.
- Keep `auto_merge_enabled=false` unless a separate policy-governed goal explicitly enables it.
- Notifications require both config `notification_enabled=true` and CLI `-Send`.
- First real pilot tasks must be docs-only.

## Smoke Tests

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-edge-worker-register.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-edge-worker-claim.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-codex-task-runner.ps1 -DryRun
```
