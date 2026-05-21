# Mega Goal 001: Self-Observable SkyBridge Loop

## Mission

Make SkyBridge visibly observe its own autonomous development loop: local Codex activity, runner fallback activity, server ingestion, run summaries, notifications and dashboard state should form one coherent demo path.

Estimated effort: 6-10 hours of sustained Codex TUI work.

Do not implement this goal as part of workflow planning. Execute it only when explicitly selected in Codex TUI.

## Context Files To Read

- `AGENTS.md`
- `README.md`
- `ARCHITECTURE.md`
- `DEVELOPMENT.md`
- `SECURITY.md`
- `docs/codex/GOAL_MODE.md`
- `docs/codex/TUI_MASTER_GOAL.md`
- `docs/codex/AUTONOMOUS_RUNNER.md`
- `docs/dev/PROGRESS.md`
- `packages/event-schema/`
- `packages/agent-adapters/`
- `apps/server/`
- `apps/web/`
- `packages/react-widgets/`

## Staged Sub-Goals

1. Map the current self-observation path from Codex hooks and runner telemetry into server events and run summaries.
2. Add or tighten missing correlation fields so Codex, runner and manual smoke events produce useful run/session grouping.
3. Add a local demo script or documented smoke flow that sends representative self-observation events without secrets.
4. Improve dashboard or widget display for self-observation status, recent runs and important failures.
5. Add focused tests for schema validation, aggregation and any UI/state helpers touched.
6. Update docs with the validated local self-observation loop.

## Expected Commits

- `docs(loop): document self-observation flow`
- `feat(server): improve self-observation aggregation`
- `feat(web): surface self-observation status`
- `test(loop): cover self-observation event flow`

Adjust commit boundaries to the actual implementation, but keep each commit reviewable and passing.

## Checks

- Focused package tests for changed packages.
- `corepack pnpm --filter @skybridge-agent-hub/server test` when server logic changes.
- `corepack pnpm --filter @skybridge-agent-hub/web build` when web UI changes.
- `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

## Stop Conditions

Stop and record progress if:

- event correlation requires a schema-breaking change not planned in this goal;
- dashboard work expands into a full redesign;
- a server or adapter change risks exposing command output or secrets;
- checks fail for unrelated reasons after a focused repair attempt.

## Safety Boundaries

- Do not upload full prompts, stdout, stderr, JSONL logs, secrets or `.env` contents.
- Do not deploy.
- Do not change production server configuration.
- Do not weaken auth or redaction defaults.
- Do not enable runner parallelism.

## Progress Logging Requirements

- Add a dated entry to `docs/dev/PROGRESS.md` for each completed stage.
- Record demo commands and check results.
- List any deferred follow-up goals.
- Keep runtime logs under `.agent/runs` or `.data` out of Git.
