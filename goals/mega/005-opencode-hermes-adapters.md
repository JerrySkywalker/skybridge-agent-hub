# Mega Goal 005: OpenCode And Hermes Adapters

## Mission

Add first-class OpenCode and Hermes Agent adapter foundations that normalize source events into `skybridge.agent_event.v1` before they reach the server or widgets.

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
- `packages/event-schema/`
- `packages/agent-adapters/`
- `apps/server/`
- `packages/client/`
- existing Codex adapter tests and fixtures

## Staged Sub-Goals

1. Inspect existing adapter architecture and identify extension points for OpenCode and Hermes.
2. Define minimal source payload fixtures for OpenCode and Hermes based on available local docs or stable public behavior.
3. Implement normalization helpers for session, run, turn, tool, message and approval events.
4. Add tests that prove both adapters emit valid `skybridge.agent_event.v1` events.
5. Add integration docs showing how future sources should hand normalized events to the server.
6. Record unknown or speculative source fields as follow-up tasks instead of guessing deeply.

## Expected Commits

- `test(adapters): add OpenCode and Hermes fixtures`
- `feat(adapters): add OpenCode normalization`
- `feat(adapters): add Hermes normalization`
- `docs(adapters): document adapter integration`

Adjust commit boundaries to the actual implementation, but keep each commit reviewable and passing.

## Checks

- `corepack pnpm --filter @skybridge-agent-hub/event-schema test`
- `corepack pnpm --filter @skybridge-agent-hub/agent-adapters test`
- Server tests if ingestion examples change.
- `just check` before stopping, or `corepack pnpm check` if `just` is unavailable.

## Stop Conditions

Stop and record progress if:

- OpenCode or Hermes event shapes cannot be verified enough for a safe adapter contract;
- implementation would require network credentials, private API tokens or user cookies;
- the adapter would need to upload full prompts, command output or secrets by default;
- the work expands into remote-control behavior instead of telemetry normalization.

## Safety Boundaries

- Do not commit credentials or private integration configs.
- Do not add default full-output telemetry.
- Do not implement remote control in this adapter goal.
- Do not weaken schema validation or redaction.
- Do not deploy.

## Progress Logging Requirements

- Add a dated entry to `docs/dev/PROGRESS.md` for each completed stage.
- Include fixture provenance and assumptions.
- Record unverified source fields as follow-up goals.
