# Local Runtime RC Runbook

Use the bounded local runtime candidate only for non-worker components.

Safe commands:

```powershell
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-runtime.ps1 -Command apply-candidate
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-runtime.ps1 -Command start-local-session
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-runtime.ps1 -Command session-status
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-runtime.ps1 -Command stop-local-session
pwsh -ExecutionPolicy Bypass -File scripts/powershell/skybridge-local-runtime.ps1 -Command cleanup-stale-session
```

The candidate is bounded metadata. It must not start Codex workers, run workunit apply, claim tasks, run queue apply, or start unbounded loops.
