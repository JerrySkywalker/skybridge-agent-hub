# Unified Queue Dashboard

Goal 191D adds the shared read-only foundation for the Desktop and Web queue dashboards. Goal 191E hardens the Desktop refresh path so slow local bridge commands cannot freeze the resident UI. Goal 192 adds the shared Safe Actions / Queue Controls contract without enabling execution apply. Goal 193 adds shared attention events and fixture-safe notification routing. Goal 194 adds worker service readiness. Goal 195 adds manual goal queue review. Both surfaces consume shared `@skybridge-agent-hub/client` models.

## Scope

Goal 192 keeps start-one/start-queue execution disabled. It adds read-only, preview-only and reason-gated safe stop/pause controls. Future execution controls are deferred until a later reviewed goal.

## Shared Contract

The shared consumer models `campaign_summary`, `current_step_summary`, `previous_step_summary`, `step_ledger`, evidence ledger summary counts, `blockers[]`, `warnings[]`, `queue_control_readiness`, `worker_status`, `next_safe_action`, attention events and `token_printed=false`.

Goal 192 also adds `skybridge.queue_control_intent.v1`, `skybridge.queue_control_state.v1`, `skybridge.queue_control_action_response.v1`, `skybridge.queue_control_audit_event.v1`, `run_budget`, `arm_lease`, `revision` and `target_revision`. Goal 193 adds `skybridge.attention_event.v1` and notification routing decisions. Goal 194 adds `skybridge.worker_service_state.v1` and worker service readiness. Goal 195 adds `skybridge.goal_queue_review_summary.v1`. See [QUEUE_CONTROL_CONTRACT.md](QUEUE_CONTROL_CONTRACT.md), [NOTIFICATION_ATTENTION_LOOP.md](NOTIFICATION_ATTENTION_LOOP.md), [WORKER_SERVICE_MODE.md](WORKER_SERVICE_MODE.md) and [MANUAL_GOAL_QUEUE_MANAGEMENT.md](MANUAL_GOAL_QUEUE_MANAGEMENT.md).

Web uses fixture report data for the new `#/campaign-queue` route. Desktop uses the same fixture for visual QA and reads the local `runner-report` output through its Tauri bridge during normal refresh.

Desktop refresh behavior:

- status, campaign, worker and report bridge outcomes are separated;
- timeout/failure in one bridge produces a structured warning;
- report data remains visible when status fails;
- cached report JSON under `.agent/tmp/campaign-reports/` may be displayed with age when fresh report generation fails;
- overlapping refreshes use request generation tracking so stale responses are ignored.

## Readiness Mapping

Desktop and Web must treat `queue_control_readiness` as the source of truth. `can_start_one`, `can_start_queue` and apply-mode `can_resume` stay disabled when `worker_status` is `unknown`, `offline`, `stale` or `missing`.

Goal 192 shows Safe Actions / Queue Controls on Web and Desktop. Refresh, Report and Copy Safe Summary are read-only. Resume Preview, Start One Preview and Start Queue Preview are preview-only. Safe Pause, Stop Queue and Emergency Stop require reason and audit for apply. Start One Apply, Start Queue Apply, Start All, Run Forever and Worker Loop remain disabled.

Goal 193 shows an attention banner/feed on Web and an Attention Panel on Desktop. Current worker offline readiness becomes an action-required attention item. Notification routing status is shown as Desktop/Web/local-fixture/ntfy-placeholder/disabled without sending real external notifications.

Goal 194 shows a Worker Readiness Panel on Web and a Worker Service Panel on Desktop. Goal 195 adds a Manual Goal Queue Review panel on both surfaces for goal pack id, current campaign pack hash, validation result, hash drift, dependency/order status, re-import preview and archive preview. Web has no direct local process control. Desktop controls remain disabled or CLI-smoke-backed for bounded heartbeat/stop only. Start One, Start Queue, task claim, task execution and Codex worker execution remain disabled through Goal 195.

For current Goal 191 state, Desktop uses `Queue Readiness` / `Operator Readiness` as the primary status wording. Pre-190 wording is legacy and must not be the main banner after Goal 190 is complete.

## Safe Summary

The shared safe summary is `skybridge.campaign_safe_summary.v1`. It is safe to copy into PR comments or ChatGPT after checking `token_printed=false`.

It includes campaign id, current step and goal, queue readiness, blockers, warnings, worker status, worker service mode, worker service blockers, attention count, top blocker, recommended next action, goal pack id, validation result, hash drift count, dependency/order status and proposed import/update action. It excludes raw logs, raw prompts, stdout/stderr, tokens, Authorization headers and local secret paths.

Desktop Copy safe summary uses the currently cached report snapshot. It must not wait for a slow refresh or trigger a bridge call.

## Visual QA

Run fixture-only visual QA:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-queue-dashboard-visual-qa.ps1
```

The smoke refuses non-loopback bases. If Playwright is unavailable, it writes a safe skipped manifest with `fixture_only=true`, `production_endpoint_used=false` and `token_printed=false`.

The Desktop fixture includes an async timeout warning state so visual QA covers the nonfatal warning presentation.

Expected artifact locations:

- `.agent/tmp/desktop-visual-qa/desktop-queue-dashboard.png`;
- `.agent/tmp/desktop-visual-qa/manifest.json`;
- `.agent/tmp/queue-dashboard-web-visual-qa/campaign-queue-desktop.png`;
- `.agent/tmp/queue-dashboard-web-visual-qa/manifest.json`.

Screenshots are fixture-only local artifacts. Do not capture production endpoints or secret-bearing pages.
