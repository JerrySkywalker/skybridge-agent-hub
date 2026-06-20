# Worker Heartbeat Proof

`skybridge-worker-heartbeat-proof.ps1` is an operator proof for bringing exactly one authorized local worker online for heartbeat visibility only.

It does not claim tasks, run Codex, poll queues, apply campaign queues, advance campaign metadata, call `start-one`, call `run-until-hold` or unpause project control.

## Run

Load the local SkyBridge operator environment first:

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
```

Then run the proof with the explicit heartbeat-only acknowledgement:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-worker-heartbeat-proof.ps1 `
  -HeartbeatOnly `
  -Json
```

The default worker id is `jerry-win-local-01`. To use a local worker profile outside the repository:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-worker-heartbeat-proof.ps1 `
  -ConfigFile "$HOME\.skybridge\worker.$env:COMPUTERNAME.json" `
  -ProjectId skybridge-agent-hub `
  -HeartbeatOnly `
  -Json
```

Without `-HeartbeatOnly`, the script fails before registration or heartbeat.

## Output Contract

The script emits:

```text
schema = skybridge.worker_heartbeat_proof.v1
ok = true | false
worker_id = string
heartbeat_sent = true | false
worker_online_after = true | false
tasks_claimed = false
codex_run_called = false
queue_apply_called = false
campaign_metadata_advanced = false
start_one_called = false
run_until_hold_called = false
project_control_unpaused = false
token_printed = false
```

The script may include safe worker, task-summary and project-control summaries. It must not print tokens, cookies, auth headers, webhook URLs, raw environment files, raw logs, raw Hermes responses or production config.

## Readiness Semantics

Worker heartbeat is not task execution. A successful heartbeat only proves that SkyBridge can see one authorized worker as online.

For self-bootstrap readiness, this can remove the `worker_offline` blocker when no other heartbeat blocker exists. It must not imply that task execution is safe.

After the proof:

- `workers.online` should be at least `1`;
- `online_worker_ids` should include the authorized local worker;
- `worker_offline` should no longer appear as a blocker;
- `project_control.state` must remain `paused`;
- `allow_start_one`, `allow_run_until_hold`, `can_start_one` and `can_run_until_hold` remain false unless their separate execution gates are satisfied.

## Smoke

Run the fixture-only smoke:

```powershell
corepack pnpm smoke:worker-heartbeat-proof
```

The smoke starts an isolated local server and verifies:

- missing `-HeartbeatOnly` fails safely;
- heartbeat-only mode does not claim the seeded queued task;
- Codex is not called;
- queue apply is not called;
- campaign metadata is not advanced;
- project control remains paused;
- output keeps `token_printed=false`;
- online, stale and offline worker classification remains deterministic.
