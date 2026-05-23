# Supervisor Escalation

Hermes and the CI Guardian need a notification policy that works before SkyBridge's own Notification Center is reliable. During SkyBridge development, phone delivery uses the bootstrap notifier first.

## Escalation Levels

`info`:
Iteration completed, CI green, nightly report ready or no queued goal.

`warning`:
CI repair retry, SkyBridge server unavailable, local check failed once, GitHub inspection degraded or queue metadata missing.

`high`:
Repeated failure approaching the repair limit, PR stuck in failing state or controller cannot safely commit because the worktree is unexpected.

`urgent`:
Safety boundary detected, secret or production-risk signal, max repair attempts exhausted, blocked iteration, failed Codex worker or production deployment attempt.

Bootstrap notifier severities are `info`, `warning` and `urgent`; the `high` policy maps to `warning` unless the condition also crosses an urgent boundary.

## Notification Routing

Stage 1:
Call `scripts/powershell/notify-bootstrap.ps1` directly. This is required for urgent and blocked lifecycle messages.

Stage 2:
Dual-write direct bootstrap notification plus safe SkyBridge iteration events when `/v1/iterations` is reachable.

Stage 3:
Use SkyBridge Notification Center as primary after it is ready for self-supervision, with bootstrap direct notification as fallback for outage, urgent safety boundary and repeated failure.

## Event Examples

Warning repair retry:

```json
{
  "type": "iteration.ci_failed",
  "payload": {
    "iteration_id": "iter_pr_12",
    "pr_number": 12,
    "attempt": 2,
    "escalation": "warning"
  }
}
```

Urgent blocked run:

```json
{
  "type": "iteration.blocked",
  "payload": {
    "iteration_id": "iter_pr_12",
    "pr_number": 12,
    "reason": "max_repair_attempts_exhausted",
    "escalation": "urgent",
    "raw_logs_included": false
  }
}
```

Bootstrap direct notification:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\notify-bootstrap.ps1 `
  -Title "SkyBridge CI blocked" `
  -Message "PR #12 still fails after repair attempts." `
  -Severity urgent
```

## Payload Safety

Escalation messages may include:

- iteration ID;
- project ID;
- branch;
- PR number;
- state;
- attempt count;
- short blocked reason;
- check names.

They must not include raw prompts, patches, stdout, stderr, command output, Codex JSONL, tokens, cookies, private keys or production config values.
