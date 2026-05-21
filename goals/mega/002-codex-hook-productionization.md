# Mega Goal 002: Codex Hook Productionization

## Mission

Turn the Codex hook and Codex exec adapter path into a reliable, documented, redacted production-quality local integration for SkyBridge.

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
- `packages/agent-adapters/`
- `packages/event-schema/`
- `apps/server/`
- `scripts/powershell/`

## Staged Sub-Goals

1. Audit the current Codex hook and exec adapter behavior against `skybridge.agent_event.v1`.
2. Tighten event normalization for session, run, turn, tool, approval, message, diff and file event families where needed.
3. Harden redaction so commands, tool inputs and outputs are summarized safely by default.
4. Add installation and local verification docs for Codex hook usage.
5. Add focused tests and fixtures for representative Codex hook payloads and malformed inputs.
6. Add an operator-facing troubleshooting section for hook delivery, server connectivity and skipped notifications.

## Expected Commits

- `test(codex): add hook adapter fixtures`
- `feat(codex): harden hook normalization`
- `docs(codex): document hook installation and troubleshooting`

Adjust commit boundaries to the actual implementation, but keep each commit reviewable and passing.

## Checks

- `corepack pnpm --filter @skybridge-agent-hub/event-schema test`
- `corepack pnpm --filter @skybridge-agent-hub/agent-adapters test`
- Server tests if ingestion behavior changes.
- `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

## Stop Conditions

Stop and record progress if:

- a Codex payload format is uncertain and cannot be verified locally;
- a required change would send raw command output or secrets by default;
- hook installation requires modifying global user config in a way that is not explicitly approved;
- a compatibility change would break existing stored events.

## Safety Boundaries

- Do not commit local Codex config that contains private paths, tokens or cookies.
- Do not weaken event validation.
- Do not upload full command output by default.
- Do not deploy.
- Do not modify production secrets or `/opt/skybridge-agent-hub/.env`.

## Progress Logging Requirements

- Add a dated entry to `docs/dev/PROGRESS.md` for each completed stage.
- Include test fixture coverage and redaction decisions.
- Record any unknown Codex event shapes as follow-up goals.
