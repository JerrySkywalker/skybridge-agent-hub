# Progress Log

## 2026-05-21

- Mega Goal 003 Stages 1-12: productized the Operator Console across server APIs, demo data, typed client helpers, React widgets, web app layout, SSE-backed timeline behavior, compact Web Component embed, smoke validation, CI wiring and docs.
- Commits created: `docs(ui): design operator console`, `feat(server): add console query APIs`, `test(data): add demo event seeding`, `feat(client): add typed dashboard API helpers`, `feat(widgets): add operator console widgets`, `feat(web): build operator console overview`, `feat(embed): improve compact status component`, `test(smoke): add operator console smoke script`, `ci: harden dashboard validation`.
- Checks run so far: server test/typecheck, client test/typecheck, react-widgets test/typecheck, web build, web-components test/typecheck/build, Operator Console smoke with temporary SQLite, Docker dev/test compose config.
- Operator Console smoke result: temporary local server returned 12 demo events, 3 runs, 1 failed run, 3 notifications, 5 attention items and existing web build artifacts.
- Known gaps: no browser screenshot artifact was captured in this session; validation used build, static render tests and HTTP smoke scripts. Remote-control UI remains intentionally out of scope.
- Mega Goal 002 Stage 1: audited the Codex local integration path across hook and exec adapters, PowerShell hook scripts, server ingestion/query behavior, client query helpers, the self-observation panel and Codex docs. Added `docs/codex/CODEX_LOCAL_INTEGRATION.md` to define the production local path, supported Codex event families, hook mappings, spool/replay expectations and redaction defaults.
- Stage 1 check: documentation-only design change; no code check required before this commit.
- Mega Goal 002 Stages 2-3: added representative Codex hook stdin JSON fixtures for session startup/resume, prompt submit, Bash pre/post success/failure, apply_patch, permission request, stop and malformed/minimal payloads. Hardened Codex hook normalization for `tool.failed`, `file.edited`, `diff.updated`, bounded nested payloads, command/output summaries and secret-like redaction.
- Stages 2-3 checks: `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook test` and `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook typecheck` passed.
- Mega Goal 002 Stages 4-5: productionized Codex PowerShell hook operations with a bounded fail-open dashboard hook, local JSONL queue/audit spool, replay script, dry-run installer, restore script and fixture-driven hook tester. Installer dry-run preserves Codex hook array shape and writes only with explicit `-Apply`.
- Stages 4-5 checks: PowerShell parse checks passed for all scripts; `test-codex-hook-event.ps1 -RequireSpool` passed with 10 fixtures and 12 normalized queued events; `replay-codex-hook-spool.ps1 -WhatIfOnly` reported 12 queued events without mutation.
- Mega Goal 002 Stage 6: extended event queries with `from`/`to` time-window filters and expanded run summaries with active tool counts, cwd, goal and latest safe message summary derived only from normalized/redacted events.
- Stage 6 checks: `corepack pnpm --filter @skybridge-agent-hub/event-schema typecheck`, `corepack pnpm --filter @skybridge-agent-hub/client typecheck`, `corepack pnpm --filter @skybridge-agent-hub/server test` and `corepack pnpm --filter @skybridge-agent-hub/server typecheck` passed.
- Mega Goal 002 Stage 7: added `smoke-codex-hook-integration.ps1` for online hook delivery plus offline spool/replay. Fixed the PowerShell hook to drop null optional fields before delivery so server validation accepts generated events.
- Stage 7 checks: script parse passed; smoke passed on `http://127.0.0.1:8798` with 10 fixtures, 12 persisted Codex events, 4 Codex run summaries, 12 offline queued events and 12 replayed events.
- Mega Goal 002 Stage 8: added a Codex Integration dashboard panel that surfaces recent Codex runs, latest hook event, active/failed tool counts and spool count when available from events.
- Stage 8 checks: `corepack pnpm --filter @skybridge-agent-hub/react-widgets test`, `corepack pnpm --filter @skybridge-agent-hub/react-widgets typecheck` and `corepack pnpm --filter @skybridge-agent-hub/web build` passed.
- Mega Goal 002 Stage 9: updated README, DEVELOPMENT, SECURITY, `docs/codex/HOOKS.md` and `docs/codex/CODEX_LOCAL_INTEGRATION.md` with Codex hook install, smoke, replay, redaction, spool cleanup/privacy and troubleshooting guidance.
- Mega Goal 001 Stage 1: mapped the current self-observation loop in `docs/codex/SELF_OBSERVATION_LOOP.md`, including Codex hooks, Codex exec JSON, runner telemetry, manual smoke events, server ingestion/query/SSE, notification placeholders and dashboard consumption.
- Stage 1 check: documentation-only change; no code check required before this commit.
- Mega Goal 001 Stage 2: added scoped event filtering and a run detail API for self-observation drill-in; run summaries now include safe agent/node IDs, tool and notification counts, lifecycle, branch and goal metadata derived from redacted payloads.
- Stage 2 checks: `corepack pnpm --filter @skybridge-agent-hub/event-schema test`, `corepack pnpm --filter @skybridge-agent-hub/event-schema typecheck`, `corepack pnpm --filter @skybridge-agent-hub/client typecheck`, `corepack pnpm --filter @skybridge-agent-hub/server test` and `corepack pnpm --filter @skybridge-agent-hub/server typecheck` passed.
- Mega Goal 001 Stage 3: added `scripts/powershell/smoke-self-observation.ps1` to send representative local loop events, query the run detail API, verify scoped event lookup and report notification placeholder state without requiring secrets.
- Stage 3 checks: PowerShell parse check passed; local server smoke run passed on `http://127.0.0.1:8797` with a temporary SQLite file.
- Mega Goal 001 Stage 4: added a self-observation dashboard panel and summary helper that distinguish Codex, runner, smoke and notification events while surfacing active/failed run state.
- Stage 4 checks: `corepack pnpm --filter @skybridge-agent-hub/react-widgets test`, `corepack pnpm --filter @skybridge-agent-hub/react-widgets typecheck` and `corepack pnpm --filter @skybridge-agent-hub/web build` passed. The in-app Browser backend was unavailable (`iab` could not be acquired), so fallback local HTTP checks verified the dashboard returned HTTP 200, the API was healthy and the smoke run appeared in `/v1/runs`.
- Mega Goal 001 Stage 5: added focused adapter tests for Codex hook fallback correlation and Codex exec JSON redaction; tightened Codex exec normalization so free-form summaries are represented by presence/length metadata instead of being retained.
- Stage 5 checks: `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-exec-json test`, `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-exec-json typecheck`, `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook test` and `corepack pnpm --filter @skybridge-agent-hub/adapter-codex-hook typecheck` passed.
- Mega Goal 001 Stage 6: updated README, architecture, development, self-observation loop docs and the active mega goal with the validated local smoke flow, new query APIs and deferred follow-up for deeper dashboard run drill-in.
- Stage 6 check: `just check` passed.
- Read the repository instructions, architecture docs and staged goals.
- Implemented a typed `skybridge.agent_event.v1` schema with validation and tests.
- Built the server MVP with health, event ingestion, event listing, run summaries, SSE stream, notification endpoints and local JSON persistence.
- Added ntfy provider behavior with safe placeholder recording when credentials are missing.
- Added Codex hook normalization and guard-hook redaction/safety updates.
- Added local sidecar event forwarding.
- Implemented React widgets, dashboard shell and a framework-neutral status Web Component.
- Updated development, hook and architecture docs for local operation.
- Validation: `corepack pnpm check` passed; Docker dev/test compose config passed; local server smoke test passed for health, event ingest, event list and run summaries.
- Environment note: `pnpm` and `just` are not directly on PATH here. Commands work through `corepack pnpm`; `just check` could not be run because `just` is not installed.
- Replaced MVP JSON-first persistence with SQLite-backed server persistence at `.data/skybridge.sqlite`; existing `.data/skybridge-store.json` or `SKYBRIDGE_DATA_FILE` data is imported once and left untouched.
- Added focused hardening tests for SQLite persistence/restart behavior, JSON migration, notification trigger placeholder recording, SSE replay, Codex hook parsing/redaction, and React widget static rendering.

## v0.2.0-sqlite-mvp verification

- `just check`: passed.
- Server health: passed.
- Persistence: sqlite.
- Local DB file observed at `apps/server/.data/skybridge.sqlite` when running server via pnpm filter.
- Git tag: `v0.2.0-sqlite-mvp`.

## Engineering discipline update

- Added repository line-ending policy with LF for source/config/docs/CI files and CRLF for Windows-first PowerShell scripts.
- Standardized server default SQLite and legacy JSON migration paths on repository-root `.data/`, while keeping `SKYBRIDGE_DB_FILE` and `SKYBRIDGE_DATA_FILE` overrides.
- Hardened `/v1/events` so invalid event payloads return HTTP 400 validation details instead of surfacing as server errors.
- Codified small-step autonomous Git workflow: split goals into logical commits, run the smallest relevant check before each commit, run `just check` before stopping, and push after completed passing goals.

## Open-source homepage and autonomous runner foundation

- Rewrote the top-level README as a public open-source project homepage with quick start, architecture, event model, API examples, development commands, roadmap, security stance and contributing guidance.
- Hardened `scripts/powershell/yolo-runner.ps1` into a single-worker queue runner MVP for `goals/ready/*.md`.
- Added runner claim metadata, per-run logs under `.agent/runs/<timestamp>-<goal-id>/`, Codex JSONL output, standard checks, limited repair rounds, branch push and optional PR creation.
- Added `config/runner.example.json` and `docs/codex/AUTONOMOUS_RUNNER.md`.
- Kept autonomous execution intentionally local, non-deploying and single-threaded with `MaxParallel = 1`.

## Codex TUI Master Goal workflow

- Added `goals/00_AUTONOMOUS_MASTER_GOAL.md` as the operating source of truth for long-horizon Codex TUI development.
- Added `docs/codex/TUI_MASTER_GOAL.md` and updated goal-mode docs to make Codex TUI the recommended primary development workflow.
- Added `goals/mega/` with five 6-10 hour mega goals:
  - `001-self-observable-skybridge-loop`
  - `002-codex-hook-productionization`
  - `003-dashboard-productization`
  - `004-ci-cd-staging-foundation`
  - `005-opencode-hermes-adapters`
- Repositioned `scripts/powershell/yolo-runner.ps1` as the fallback batch/background processor for bounded `goals/ready/*.md` child goals.
