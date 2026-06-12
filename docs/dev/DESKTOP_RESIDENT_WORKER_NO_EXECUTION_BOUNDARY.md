# Desktop Resident Worker No-Execution Boundary

Goal 217 installs resident worker infrastructure only. It deliberately keeps all execution pathways disabled while the UI, local supervisor, heartbeat, reports, and preview controls are validated.

## Boundary

The resident worker must not:

- run Codex as a worker;
- create workunits;
- create tasks;
- claim tasks;
- create task PRs;
- enable queue apply or multi-workunit apply;
- auto-start execution on app launch;
- enable remote execution;
- dispatch arbitrary shell commands;
- require admin privileges;
- mutate `powercfg`, registry, Windows sleep settings, startup entries, services, production config, branch protection, or secrets;
- persist raw prompts, transcripts, stdout, stderr, worker logs, CI logs, GitHub logs, raw diffs, tokens, private keys, cookies, or secret-bearing paths.

## Future Enablement Gate

A future goal must add server control plane policy, failure budget enforcement, audit retention, operator approval flow, and packaging/installer behavior before execution can be enabled. That goal must explicitly authorize any execution path and add new smokes that prove the approval and audit gates fail closed.

## Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-no-codex-execution.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-local-supervisor-no-task-claim.ps1
pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/powershell/smoke-desktop-resident-worker-no-enabled-execution-buttons.ps1
```
