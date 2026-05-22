# Progress Log

## 2026-05-22

- Nightly CI/CD Guardian round 12: inspected draft PR #10 and confirmed GitHub checks were green, reran `corepack pnpm check`, then expanded the shared PowerShell redaction parity smoke with a `ConvertFrom-Json` array fixture. The new fixture proves nested Authorization fields are replaced and raw `tool_result`/`stderr` content is bounded when PowerShell runner or hook telemetry receives JSON arrays. Validation passed with the focused shared redaction smoke and PowerShell parse validation.
- Nightly CI/CD Guardian round 11: inspected draft PR #10 and confirmed GitHub checks were green, reran `corepack pnpm check`, then added a bounded local audit JSONL export endpoint at `/v1/audit/export`. The export reuses durable safe audit records, accepts the same filters and bounded limit as `/v1/audit`, returns headers that state raw payloads are excluded, and is documented as local pull-only fixture-safe output. Validation passed with focused server tests, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 10: inspected draft PR #10 and current local state, reran `corepack pnpm check`, then tightened durable audit trail coverage with SQLite restart fixtures for node heartbeat, notification routing and failed-run audit records. The server test now proves those audit records keep only safe metadata, retain source/action/actor/safety decision fields, and do not return private keys, notification bodies, tokens, stderr or prompts. Focused validation passed with `corepack pnpm --filter @skybridge-agent-hub/server test`.
- Nightly CI/CD Guardian round 9: inspected draft PR #10 and current local state, then hardened shared PowerShell redaction consumption for generic dictionaries and `ConvertFrom-Json` object values. The shared redaction parity smoke now proves `PSCustomObject` payloads redact token fields, bearer values and raw output fields before runner or hook telemetry can emit them. Validation passed with shared redaction parity smoke, PowerShell parse validation, runner dry-run smoke, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 8: inspected draft PR #10 and confirmed latest GitHub checks were green, then added a fixture-only browser visual QA `manifest.json` for future screenshot artifact review. The browser visual QA runner now refuses non-loopback web bases, records the expected route/viewport/text matrix beside screenshots when Playwright is installed, and keeps the Playwright-unavailable skip-safe path. Validation passed with `node --check scripts/browser-visual-qa.mjs`, `corepack pnpm smoke:browser-visual-qa`, PowerShell parse validation, `corepack pnpm check` and `just check`.
- Nightly CI/CD Guardian round 7: inspected draft PR #10 and confirmed latest GitHub checks were green, reran `corepack pnpm check`, and tightened browser visual QA follow-up docs with the exact desktop/mobile/embed route and viewport matrix plus required visible panels. The browser visual QA backlog now marks viewport documentation complete and tracks the artifact manifest as the next safe CI upload prerequisite. Validation passed with `corepack pnpm check`, `corepack pnpm smoke:browser-visual-qa` on the Playwright-unavailable skip-safe path, and PowerShell parse validation.
- Nightly CI/CD Guardian round 6: expanded the shared TypeScript/PowerShell redaction parity smoke to cover secret keys, bearer values, API keys, private-key markers and raw prompt/patch/output fields; documented redaction policy versioning; and fixed the server SQLite persistence restart test so local `NTFY_TOPIC_URL` settings cannot make it perform a real provider send. Validation passed with shared redaction parity smoke, PowerShell parse validation, focused server tests and `corepack pnpm check`.
- Nightly CI/CD Guardian round 5: upgraded the browser visual QA scaffold into an optional executable Playwright path that starts fixture-backed temporary server/web processes, checks primary dashboard/embed rendering, and captures local screenshots when Playwright is installed while preserving the skip-safe default path for CI without browser dependencies.
- Nightly CI/CD Guardian round 4: extended shared PowerShell redaction consumption into runner telemetry, added policy metadata to runner payloads, added a loopback dry-run runner redaction smoke, and wired that smoke into nightly local validation. Validation passed with `corepack pnpm check`, runner dry-run redaction smoke, shared redaction parity smoke and PowerShell parse validation.
- Nightly CI/CD Guardian round 3: refactored Codex PowerShell hook redaction into `scripts/powershell/shared-redaction.ps1`, added a TypeScript/PowerShell shared-rule parity smoke, wired that smoke into nightly local validation, and updated release/security/backlog docs. Validation passed with `corepack pnpm check`, focused event-schema and Codex hook checks, PowerShell parse validation, hook fixture smoke, redaction parity smoke, and `nightly-local-validation.ps1 -SkipDockerBuilds`.
- Nightly CI/CD Guardian round 2: added a durable audit trail skeleton with SQLite-backed append-only audit rows for auditable events, `/v1/audit` filters, client query support, dogfooding smoke assertions for safe audit metadata, and refreshed release/audit docs. Validation passed with `corepack pnpm check`, focused server/client checks, PowerShell parse validation, multi-agent and dogfooding smokes, and `nightly-local-validation.ps1 -SkipDockerBuilds`.
- Super Goal 005-014 release train: completed the first platform release train pass across multi-agent adapters, sidecar/node foundation, notification routing/jobs, shared redaction/security docs, demo/dogfooding assets, approval API, metrics endpoint, self-hosting docs, roadmap and v0.9 release candidate notes.
- Commits created so far: `feat(adapters): add multi-agent adapter foundation`, `feat(sidecar): add safe node registry foundation`, `feat(notifications): add provider routing job foundation`, `security: add shared redaction rules`.
- Checks run so far: focused event-schema, adapter, sidecar, notification provider, server and client tests/typechecks passed for touched areas.
- Known gaps intentionally deferred to backlog goals: real WSS implementation, browser visual QA, mobile readiness, production deployment hardening, public docs site and external contributor onboarding.
- Continuation hardening: added physical OpenCode/Hermes fixture files, provider skip tests across the matrix, API examples, self-hosting dry-run smoke, release train audit notes, and a PowerShell shared-redaction follow-up goal.
- Second continuation hardening: added dashboard panels for metrics and notification provider status plus a multi-agent platform smoke covering sources, demo events, nodes, providers, approvals and metrics together.
- PR #9 audit hardening: repaired Linux PowerShell `Start-Process -WindowStyle` usage in smoke scripts, added Docker Buildx setup for image cache support, added `docs/release/PR9_GAP_AUDIT.md`, expanded PR-created backlog goals with background/tasks/completion/safety sections, and added a safe derived `/v1/audit` endpoint plus client/test coverage.
- PR #9 local validation passed: `corepack pnpm check`, Docker dev/test/prod compose config, PowerShell parse validation, Operator Console smoke, release dry-run smoke, self-hosting dry-run smoke, Codex hook integration smoke with temporary server/spool, multi-agent platform smoke, dogfooding smoke with temporary server, release candidate smoke, self-observation smoke against a temporary server, and local server/web Docker image builds.
- Mega Goal 004 Stages 1-15: completed the release, CI/CD, container, staging dry-run and operations foundation without deploying or touching production secrets.
- Commits created: `docs(ops): design CI/CD and release plan`, `ci: harden public PR checks`, `ci: harden AI branch validation`, `build(docker): harden production images`, `ci: publish images to GHCR`, `deploy: harden production compose template`, `deploy: add staging dry-run workflow`, `deploy: harden backup and rollback scripts`, `deploy: add notification hooks`, `ci: add release tag workflow`, `deploy: add staging dry-run workflow`, `test(ops): add release dry-run smoke`, `ci: publish smoke artifacts safely`, `security: document CI/CD threat model`.
- Final checks passed: `corepack pnpm check`, `just check`, Docker dev/test/prod compose config, PowerShell parse validation, release dry-run smoke, Operator Console smoke with temporary SQLite, Codex hook integration smoke with temporary server/spool, server Docker image build and web Docker image build.
- Staging dry-run result: missing `.env` was reported without printing secrets, compose rendered successfully and no containers were started or changed.
- Known gaps: release workflows are syntax-reviewed and locally smoke-validated but not executed on GitHub in this session; real staging or production deployment remains intentionally manual and outside this goal.

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
