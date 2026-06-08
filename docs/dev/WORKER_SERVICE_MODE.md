# Worker Service Mode

Goal 194 adds the worker service mode foundation. It does not enable queue execution.

## Contract

The shared model is `skybridge.worker_service_state.v1`.

It reports:

- `worker_service_state=true`;
- `worker_id` and `worker_profile`;
- `mode`: `offline`, `standby`, `ready`, `paused`, `stopping` or `error`;
- `heartbeat_at` and `service_started_at`;
- `current_task_id`;
- `can_claim_tasks=false`;
- `can_execute_tasks=false`;
- `stop_requested` and `pause_requested`;
- `capability_matrix`;
- `readiness_blockers`;
- `token_printed=false`.

The capability matrix allows status, heartbeat, pause and stop metadata only. It explicitly keeps `task_claim`, `task_execute`, `codex_execute`, `pr_create` and `arbitrary_shell` false.

## Standby Heartbeat Loop

`scripts/powershell/skybridge-worker-service.ps1` provides a bounded local supervisor wrapper:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service.ps1 -Command status -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service.ps1 -Command start-standby -Apply -MaxHeartbeats 2 -IntervalSeconds 0 -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-worker-service.ps1 -Command stop -Apply -Reason "operator stop" -Json
```

The apply commands write only safe local metadata under ignored `.agent/tmp/worker-service/`. They never poll tasks, claim tasks, start Codex, create PRs or expose arbitrary shell execution.

## Readiness Gates

Worker service readiness checks:

- clean worktree;
- known campaign and current Goal 194;
- active tasks `0`;
- stale leases `0`;
- runner lock `none` or `released`;
- token availability as a boolean only;
- valid worker profile name;
- service mode `standby` or `ready`.

Even if standby heartbeat is present, `ready_for_start_one_gate=false`, `can_claim_tasks=false` and `can_execute_tasks=false` in Goal 194. Queue start controls remain disabled with `execution_disabled_until_goal_195`.

## Desktop And Web

Desktop shows a Worker Service Panel with service status, heartbeat age, current task id, capability matrix, readiness blockers, recommended action and disabled local standby controls. The only implemented local mutations are CLI smokes for bounded heartbeat/stop metadata.

Web shows a Worker Readiness Panel with worker service status, capability and blockers. Web has no direct local process control.

Both surfaces keep Start One, Start Queue, task claim and execution disabled.

## Goal 195 Preparation

This goal establishes the standby/readiness vocabulary needed for Goal 195. Goal 195 can add a reviewed Start One gate on top of this contract, but it must still add explicit approval, arm leases, audit and conflict handling before any real task claim or execution is allowed.

## Validation

Run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-standby-heartbeat.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-no-task-claim.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-stop-requested.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-readiness-gates.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-no-arbitrary-shell.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-no-secrets.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-worker-service-panel.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-worker-readiness-panel.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-queue-readiness-worker-service-integration.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-worker-service-clean-worktree.ps1
```
