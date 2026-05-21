# Mega Goal 003: Dashboard Productization

## Mission

Move the SkyBridge web dashboard from MVP shell toward a practical daily operator console for monitoring agent runs, failures, notifications and current activity.

Estimated effort: 6-10 hours of sustained Codex TUI work.

Do not implement this goal as part of workflow planning. Execute it only when explicitly selected in Codex TUI.

## Context Files To Read

- `AGENTS.md`
- `README.md`
- `ARCHITECTURE.md`
- `DEVELOPMENT.md`
- `SECURITY.md`
- `docs/codex/TUI_MASTER_GOAL.md`
- `docs/dev/PROGRESS.md`
- `apps/web/`
- `packages/client/`
- `packages/react-widgets/`
- `packages/web-components/`
- `apps/server/`

## Staged Sub-Goals

1. Audit the existing dashboard flows, data dependencies, loading states and error states.
2. Improve run list, run detail and event timeline presentation for scanning and repeated use.
3. Add notification center improvements for important state changes and skipped delivery records.
4. Improve responsive behavior without introducing a marketing-style landing page.
5. Add or update client/widget tests for state mapping and UI rendering.
6. Verify the local web UI with a browser smoke test and screenshots where practical.
7. Update docs for the current dashboard workflows.

## Expected Commits

- `feat(web): improve run monitoring views`
- `feat(web): improve notification center states`
- `test(web): cover dashboard state mapping`
- `docs(web): document dashboard workflows`

Adjust commit boundaries to the actual implementation, but keep each commit reviewable and passing.

## Checks

- `corepack pnpm --filter @skybridge-agent-hub/client test`
- `corepack pnpm --filter @skybridge-agent-hub/react-widgets test`
- `corepack pnpm --filter @skybridge-agent-hub/web build`
- Browser smoke test against the local dashboard when UI changes are substantial.
- `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

## Stop Conditions

Stop and record progress if:

- UI changes require new backend APIs not scoped in this goal;
- the dashboard starts drifting into a marketing homepage;
- responsive layout cannot be verified due to local tooling failure;
- a visual change would hide failure, approval or notification states.

## Safety Boundaries

- Do not add telemetry that exposes secrets or full command output.
- Do not weaken auth assumptions for future remote control.
- Do not deploy.
- Do not remove existing tests only to pass checks.

## Progress Logging Requirements

- Add a dated entry to `docs/dev/PROGRESS.md` for each completed stage.
- Include browser smoke URLs, screenshot locations if any and check results.
- Record deferred UI/API follow-ups.
