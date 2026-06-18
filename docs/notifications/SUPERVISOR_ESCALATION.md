# Supervisor Escalation

Hermes and the CI Guardian need a notification policy that works before SkyBridge's own Notification Center is reliable. During current self-bootstrap readiness, administrator escalation uses cloud Hermes to reach Jerry over WeChat or WeCom. SkyBridge Notification Center and Jerry's future custom notify gateway remain long-term provider interfaces, not the current bootstrap blocker.

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

Current bootstrap:
SkyBridge hold, `ask_human` or blocker state emits a safe escalation summary to cloud Hermes. Hermes is responsible for administrator delivery over WeChat or WeCom. Readiness blocks on `admin_escalation_unavailable` when this path cannot send a blocker notice.

Future primary:
Use SkyBridge Notification Center or Jerry's custom notify gateway after they are ready for self-supervision.

Future fallback:
Hermes WeChat escalation and/or the bootstrap direct notifier stay available for outage, safety-boundary and repeated-failure alerts.

Stage 1:
Use Hermes WeChat or WeCom escalation for current bootstrap blockers. `scripts/powershell/notify-bootstrap.ps1` remains the direct fallback path and still requires explicit `-Send` for real delivery.

Stage 2:
Dual-write direct bootstrap notification plus safe SkyBridge iteration events when `/v1/iterations` is reachable.

Stage 3:
Use SkyBridge Notification Center as primary after it is ready for self-supervision, with bootstrap direct notification as fallback for outage, urgent safety boundary and repeated failure.

The readiness probe for the current path is:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-admin-escalation-readiness.ps1 -Json
```

The probe is read-only by default. It may verify Hermes health and safe configuration booleans, but it must not send a real WeChat or WeCom message by default. A future real-send path must use an explicit `-Send` or `-Apply` style flag and remain outside readiness smokes.

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

Escalation readiness and notification reports must also avoid raw Hermes responses, raw notification payloads, webhooks and auth headers. Required safety fields include `token_printed=false`, `raw_response_included=false` and `real_send_performed=false` for default readiness probes.
