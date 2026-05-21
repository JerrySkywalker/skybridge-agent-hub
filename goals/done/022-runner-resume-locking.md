# Goal 022: Runner Resume and Locking Hardening

## Background

The autonomous runner now moves goals through `ready`, `doing`, `done` and `failed`, and writes claim metadata. It still needs stronger recovery behavior for interrupted runs before parallelism can be considered.

## Tasks

- Add explicit lock files with stale-lock detection.
- Add a safe resume path for goals already in `goals/doing`.
- Detect branch/goal mismatches before invoking Codex.
- Preserve failed run context without overwriting previous claims.
- Add focused tests or dry-run fixtures for interrupted-run scenarios.

## Completion Criteria

- A killed runner can be restarted without losing or duplicating a claimed goal.
- Stale claims are visible and recoverable.
- `MaxParallel` remains `1`.
- `just check` or `corepack pnpm check` passes.

## Prohibited Changes

- Do not implement parallel execution.
- Do not weaken safety boundaries.
- Do not add production service deployment.
