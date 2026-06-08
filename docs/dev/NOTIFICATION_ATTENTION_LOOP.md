# Notification Attention Loop

Goal 193 adds the notification and attention loop foundation. It does not enable queue execution.

## Attention Event Model

The shared model is `skybridge.attention_event.v1` in `@skybridge-agent-hub/client`.

Each event includes `attention_event=true`, `attention_level`, `source`, campaign/current-step/goal ids, `event_type`, `message`, `recommended_action`, timestamps, acknowledgement state and `token_printed=false`.

Supported event types include `worker_offline`, `queue_blocked`, `human_approval_required`, `goal_ready`, `goal_completed`, `pr_created`, `ci_failed`, `stale_lease`, `safe_action_applied`, `emergency_stop_requested`, `notification_delivery_skipped` and `notification_delivery_fixture`.

`deriveAttentionEvents(report)` derives events from the campaign report, queue-control readiness, blockers, warnings, required human actions, worker status, PR/CI evidence and optional queue-control audit events. For the current Goal 193 state, `worker_offline` derives an `action_required` attention event. It is display-only and does not trigger execution.

## Notification Routing Matrix

The routing matrix is fixture-safe by default:

| Route | Default status | Behavior |
| --- | --- | --- |
| `desktop_only` | `enabled` | Render in SkyBridge Desktop. |
| `web_banner` | `enabled` | Render in the Web campaign queue banner/feed. |
| `local_fixture_notification` | `fixture_only` | Writes ignored local fixture ledger entries only when explicitly invoked by the fixture smoke. |
| `ntfy_placeholder` | `not_configured` | Documents where ntfy would fit later; no real send occurs by default. |
| `disabled` | `disabled` | Low-noise events stay local and are not sent externally. |

Every route has `real_external_send=false`. Goal 193 intentionally disables real external notification delivery by default because notification payloads must stay concise, redacted and reviewable before phone delivery is enabled.

## Fixture Ledger

Fixture notification attempts are written under ignored `.agent/tmp/notifications/`.

Ledger entries must not include token values, Authorization headers, raw stdout/stderr, raw prompts, raw worker logs, private keys, cookies or secret-bearing local paths.

Use:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-attention-fixture.ps1 -Command dispatch-fixture -Json
```

This writes `.agent/tmp/notifications/attention-fixture.jsonl` and returns `external_notification_sent=false` and `token_printed=false`.

## Desktop And Web Behavior

Web shows an attention banner, an attention feed and notification routing status on the Campaign Queue dashboard. Desktop shows an Attention Panel with current action-required items, worker offline state, queue blocker, recommended next action and safe notification route status.

Both surfaces remain non-executing. They do not add `start-one`, `start-queue`, `resume -Apply`, task claim, worker loop, arbitrary shell or real external notification send controls.

The copied safe summary includes `attention_count`, `top_blocker`, `recommended_next_action` and `token_printed=false`.

## Queue-Control Audit Hygiene

Goal 193 moves future fixture queue-control audit output to ignored `.agent/tmp/queue-control-audit/`. The clean-tree smoke verifies this path does not dirty the git worktree.

## Goal 194 Preparation

Goal 193 prepares worker service mode by giving operators a shared attention surface before real start-one/start-queue execution is enabled. Goal 194 can build on these fields to page the operator when worker service mode changes readiness, but execution still needs explicit approval, audit and safety gates.

## Validation

Run the focused smokes:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-attention-event-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-attention-derivation-worker-offline.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-attention-no-secrets.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-notification-routing-matrix.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-notification-fixture-ledger.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-web-attention-readonly.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-desktop-attention-readonly.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-attention-safe-summary.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-attention-no-execution-controls.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-queue-control-audit-clean-tree.ps1
```
