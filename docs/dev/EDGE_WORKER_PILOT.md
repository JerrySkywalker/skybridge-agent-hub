# Edge Worker Pilot

Status: rerun target for the Codex invocation hardening pilot.

The first real pilot must be docs-only because the edge worker executes `codex exec --sandbox danger-full-access` in a trusted local repository and then creates a draft PR. It should be launched from a clean operator shell after this branch is merged or from a disposable clone.

## Codex Invocation Hardening

The Super 141 pilot exposed a local-only blocker: `config/edge-worker.json` had `codex_command` set to a deleted `.agent/super-141-real-pilot/codex-worker.cmd` shim. The worker now treats `codex_command` as optional. If omitted, it resolves `codex` from `PATH` with `Get-Command`. If provided, it is respected and must exist; missing explicit paths fail with a clear setup error.

The worker no longer needs temporary `.agent` command shims. On Windows, `Get-Command codex` may resolve to a PowerShell shim such as `codex.ps1`; the worker launches that through `pwsh -File`. Task prompts are written to `.agent/workers/<worker>/<task>/prompt.md` and passed to `codex exec` through stdin using the `-` prompt marker, which avoids multi-word and long prompt quoting issues.

Nested Codex is instructed not to commit, push or create PRs. The worker owns safe file filtering, validation, git commit, push, draft PR creation and CI Guardian invocation.

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
- Codex resolves from explicit config or `PATH` without a temporary `.agent` shim;
- Codex updates documentation only;
- validation runs from worker config;
- worker commits safe changed files;
- worker pushes the branch and creates a draft PR;
- CI Guardian runs with auto-merge disabled unless `auto_merge_enabled` is explicitly true;
- task is marked complete with safe summary and PR URL, or failed with a bounded error summary.

## Pilot Rerun Note

For Super 142A, the safe real rerun task should update `docs/dev/EDGE_WORKER_CODEX_INVOCATION_PILOT.md` only. Run it after the parent branch has committed and pushed the invocation hardening changes, because the worker switches the active worktree to a child task branch from `origin/main`.
