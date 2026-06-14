# Control Plane Durable State Runbook

Use the durable preview state only for local/dev validation. The current persistence target is ignored `.agent/tmp/` JSON; production persistence remains future work.

Recommended validation:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-pairing-store-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-operator-approval-store-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-pairing-approval-audit-events.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-goal-223-224-report.ps1
```

Do not use this layer to create workunits, create tasks, claim tasks, create task PRs, execute Codex, apply a queue, start an unbounded loop, or dispatch shell commands from the server. The only allowed mutations are preview pairing and approval state records under ignored local storage.
