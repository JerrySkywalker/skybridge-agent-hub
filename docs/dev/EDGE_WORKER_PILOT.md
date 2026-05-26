# Edge Worker Pilot

Status: prepared, not run from this implementation branch.

The first real pilot must be docs-only because the edge worker executes `codex exec --sandbox danger-full-access` in a trusted local repository and then creates a draft PR. It should be launched from a clean operator shell after this branch is merged or from a disposable clone.

## Exact Next Command

Start the local API in one terminal:

```powershell
corepack pnpm --filter @skybridge-agent-hub/server dev
```

Register and heartbeat the worker:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Register `
  -Heartbeat `
  -Json
```

Create a tiny docs-only task through the API:

```powershell
$task = @{
  task_id = "pilot-edge-worker-docs"
  project_id = "skybridge-agent-hub"
  title = "Docs-only edge worker pilot"
  prompt_summary = "Create or update docs/dev/EDGE_WORKER_PILOT.md with a concise pilot note."
  body = "Docs-only. Do not change runtime code, secrets, deployment config or GitHub settings."
  risk = "low"
  source = "manual"
  required_capabilities = @("docs")
} | ConvertTo-Json -Depth 8

Invoke-RestMethod -Method Post `
  -Uri "http://127.0.0.1:8787/v1/tasks" `
  -ContentType "application/json" `
  -Body $task
```

Run one real worker task:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -PollOnce `
  -Json
```

Expected behavior:

- worker heartbeats before polling;
- worker claims the docs-only task;
- Codex creates a task branch from `origin/main`;
- Codex updates documentation only;
- validation runs from worker config;
- worker commits safe changed files;
- worker pushes the branch and creates a draft PR;
- CI Guardian runs with auto-merge disabled unless `auto_merge_enabled` is explicitly true;
- task is marked complete with safe summary and PR URL, or failed with a bounded error summary.

## Why It Was Not Run Here

The implementation branch already contains the edge worker changes. A real worker run would switch the worktree to a task branch from `origin/main`, which is unsafe while this super-goal branch has unmerged changes. The smoke suite covers register, heartbeat, dry-run claim, claim-only, and Codex command-shape behavior without mutating the active branch.
