# Edge Worker Loop Runbook

The Edge Worker loop is the first always-on local worker mode for SkyBridge Agent Hub. It is local-first, operator-gated and bounded by default. It heartbeats, polls queued tasks, claims one compatible task at a time, runs the existing Codex task execution path, packages draft PRs and reports safe task results back to SkyBridge.

## Start A Safe Loop

Prepare an uncommitted local config from an example:

```powershell
Copy-Item .\config\edge-worker.homepc.example.json .\config\edge-worker.json
```

Start the project control state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command start `
  -ProjectId skybridge-agent-hub `
  -MaxTasks 2
```

Run a dry-run loop first:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Loop `
  -DryRun `
  -PollIntervalSeconds 10 `
  -IdleTimeoutSeconds 60 `
  -Json
```

Run a bounded real loop only after the repository is clean, SkyBridge is reachable, GitHub CLI auth works and Codex is available:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-edge-worker.ps1 `
  -ConfigFile .\config\edge-worker.json `
  -Loop `
  -MaxTasks 2 `
  -PollIntervalSeconds 30 `
  -IdleTimeoutSeconds 600 `
  -StopOnFailure `
  -Json
```

## Stop Conditions

The loop stops when:

- `-MaxTasks` completed tasks is reached;
- `-IdleTimeoutSeconds` expires with no eligible work;
- the project control state requests stop or pause;
- degraded state is detected before starting new work;
- `-StopOnFailure` is set and a task fails.

## Degraded State

The worker pauses safely before claiming a new task when it detects:

- SkyBridge server unavailable;
- Codex command missing;
- GitHub CLI missing or unauthenticated;
- dirty repository for a real run.

Dry-run loop smokes skip Codex/GitHub/dirty-repo gates because they do not execute tasks.

## Logs

Loop logs are local-only:

```text
.agent/edge-worker-loop/<timestamp>/loop.jsonl
```

The log includes loop start, heartbeat, task poll, claim, task completion/failure, degraded state and stop reason. `.agent/edge-worker-loop/` is gitignored and must not be committed.

## Recovery After Sleep

1. Check status:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command status `
  -ProjectId skybridge-agent-hub
```

2. If the loop is paused because the machine slept, ensure the server is healthy and the repo is clean.
3. Resume control state:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-cli.ps1 `
  -Area project `
  -Command resume `
  -ProjectId skybridge-agent-hub
```

4. Restart the bounded loop command.

## Safety Model

- No production deployment.
- No secrets or local env files in SkyBridge control state.
- No raw Codex logs, prompts, patches or command output are uploaded by default.
- No task starts from a degraded real-run state.
- Auto-merge is only delegated to the existing lifecycle/merge policy.
- Parent PRs remain manual.
