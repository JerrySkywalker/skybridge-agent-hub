# Unified Queue Dashboard

Goal 191D adds the shared read-only foundation for the Desktop and Web queue dashboards. Both surfaces consume the `skybridge.campaign_run_report.v1` report contract through the shared `@skybridge-agent-hub/client` model.

## Scope

This goal is read-only. It does not add working start, queue, resume, pause, stop, emergency stop, task claim or worker-loop controls. Future execution controls are deferred to Goal 192A/192B.

## Shared Contract

The shared consumer models `campaign_summary`, `current_step_summary`, `previous_step_summary`, `step_ledger`, evidence ledger summary counts, `blockers[]`, `warnings[]`, `queue_control_readiness`, `worker_status`, `next_safe_action` and `token_printed=false`.

Web uses fixture report data for the new `#/campaign-queue` route. Desktop uses the same fixture for visual QA and reads the local `runner-report` output through its existing Tauri bridge during normal refresh.

## Readiness Mapping

Desktop and Web must treat `queue_control_readiness` as the source of truth. `can_start_one`, `can_start_queue` and apply-mode `can_resume` stay disabled when `worker_status` is `unknown`, `offline`, `stale` or `missing`.

Goal 191D shows only disabled Web placeholders: Start One disabled, Start Queue disabled and Resume disabled. Desktop shows future-control status text only, not execution buttons.

## Safe Summary

The shared safe summary is `skybridge.campaign_safe_summary.v1`. It is safe to copy into PR comments or ChatGPT after checking `token_printed=false`.

It includes campaign id, current step and goal, queue readiness, blockers, warnings and worker status. It excludes raw logs, raw prompts, stdout/stderr, tokens, Authorization headers and local secret paths.

## Visual QA

Run fixture-only visual QA:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-queue-dashboard-visual-qa.ps1
```

The smoke refuses non-loopback bases. If Playwright is unavailable, it writes a safe skipped manifest with `fixture_only=true`, `production_endpoint_used=false` and `token_printed=false`.

Expected artifact locations:

- `.agent/tmp/desktop-visual-qa/desktop-queue-dashboard.png`;
- `.agent/tmp/desktop-visual-qa/manifest.json`;
- `.agent/tmp/queue-dashboard-web-visual-qa/campaign-queue-desktop.png`;
- `.agent/tmp/queue-dashboard-web-visual-qa/manifest.json`.

Screenshots are fixture-only local artifacts. Do not capture production endpoints or secret-bearing pages.
