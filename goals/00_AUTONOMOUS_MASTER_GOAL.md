# AUTONOMOUS MASTER GOAL: SkyBridge Agent Hub

## Mission

Use Codex TUI as the primary long-horizon development driver for SkyBridge Agent Hub. The durable source of truth is this Master Goal plus the focused mega goals under `goals/mega/`.

The PowerShell `yolo-runner` remains available for queued batch/background work, but it is no longer the preferred place to plan or supervise multi-hour product development.

## Operating Model

Primary workflow:

1. Start Codex TUI from the repository root.
2. Open this file and the active `goals/mega/*.md` file.
3. Ask Codex to execute one staged sub-goal at a time.
4. Keep progress notes in the active mega goal or `docs/dev/PROGRESS.md`.
5. Make coherent commits as each sub-goal passes focused checks.
6. Run `just check` before stopping, or `corepack pnpm check` when `just` is unavailable.
7. Push the branch and open a PR when the completed work is reviewable.

Fallback workflows:

- Use `scripts/powershell/yolo-runner.ps1` for pre-sequenced Markdown goals in `goals/ready` when unattended batch processing is useful.
- Use `codex exec` for CI, scripted repair loops, and one-shot command-line automation where an interactive TUI session is unnecessary.

## Context Files To Read

Always read these before starting a mega goal:

- `AGENTS.md`
- `README.md`
- `ARCHITECTURE.md`
- `DEVELOPMENT.md`
- `SECURITY.md`
- `docs/codex/GOAL_MODE.md`
- `docs/codex/TUI_MASTER_GOAL.md`
- `docs/dev/PROGRESS.md`
- the selected `goals/mega/*.md` file

Read implementation files only as needed for the active stage.

## Long-Horizon Mega Goals

Work these in order unless a later goal becomes urgent:

1. `goals/mega/001-self-observable-skybridge-loop.md`
2. `goals/mega/002-codex-hook-productionization.md`
3. `goals/mega/003-dashboard-productization.md`
4. `goals/mega/004-ci-cd-staging-foundation.md`
5. `goals/mega/005-opencode-hermes-adapters.md`

Each mega goal is sized for 6-10 hours of sustained Codex TUI work and is expected to produce multiple small commits.

## Commit Discipline

- Split each mega goal into staged sub-goals.
- Commit after each coherent passing sub-goal.
- Prefer focused checks before each commit.
- Do not squash goal commits unless Jerry explicitly asks.
- Do not move to the next mega goal until the current goal is either complete, blocked with notes, or intentionally paused.

## Safety Boundaries

Do not:

- deploy production services;
- touch secrets, private keys, cookies, tokens, `.env` files, or `/opt/skybridge-agent-hub/.env`;
- alter root-level OpenResty, Authelia, 1Panel, Docker daemon, or production server configuration;
- run destructive cleanup commands;
- force-push `main`;
- remove tests only to make checks pass;
- weaken authentication or authorization;
- enable runner parallelism;
- upload full command output or secrets as telemetry by default.

Record blocked high-risk work as a follow-up goal instead of crossing these boundaries.

## Progress Logging

During every mega goal:

- append dated progress notes to `docs/dev/PROGRESS.md`;
- update the active mega goal when a stage is completed, skipped, or blocked;
- include commits, checks, risks, and follow-up tasks in the final summary;
- keep `.agent/runs` and other runtime logs out of Git.

## Definition Of Done

A mega goal is done only when:

- all required stages are complete or documented as intentionally deferred;
- checks pass, or failures are explicitly documented with root cause and next action;
- docs are updated for behavior or workflow changes;
- coherent sub-goal commits exist;
- the branch is pushed unless credentials or remote access block it;
- no secrets are introduced;
- residual risks and follow-up goals are listed.
