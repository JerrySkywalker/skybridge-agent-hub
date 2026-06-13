# Control Plane No Remote Execution Boundary

Goal 218 is a server/control-plane foundation only. It must not enable server-triggered task execution.

Forbidden in this goal:

- Codex execution
- workunit creation
- task creation
- task claim
- task PR creation
- queue apply
- remote execution
- arbitrary command dispatch
- start-all, start-queue or resume-apply
- production server, DNS, OpenResty, Hermes, GitHub settings or secret mutation
- raw prompt, transcript, stdout, stderr, log, diff, Authorization header, token, private key, cookie or environment dump persistence

The `/api/workers` and `/api/operator-approvals` routes are preview surfaces. They accept safe summary JSON, reject unsafe raw payloads and return explicit disabled flags.

The Web Control Plane route includes:

- Worker list
- Worker detail/status
- Resource blockers
- Queue preview
- Resident worker state
- Pairing preview
- Pending approval
- Approval state
- Completed runs
- Evidence summary
- Open review holds
- No execution enabled banner
- Remote execution disabled banner

Validation:

```powershell
corepack pnpm check
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-no-arbitrary-command-dispatch.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-control-plane-no-execution-button.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-control-plane-token-printed-false.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-server-control-plane-goal-218-report.ps1
```

Next step toward Goal 219: add authenticated local transport and audit review around these preview objects while preserving the same disabled execution defaults.
