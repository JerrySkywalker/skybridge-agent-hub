# Progress Log

## 2026-05-21

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
