# Super 162 PR Lifecycle Rerun

Status: round 1 docs-only proof task.

Super 162 validates the PR lifecycle path after PR #43 has merged. The rerun should prove that Hermes-planned, Codex-executed work can move through the edge worker, child PR creation, CI policy gates and parent task supervision without touching secrets, production configuration or deployment paths.

## Goal

Verify the post-PR #43 lifecycle path with deliberately small documentation tasks:

- Hermes creates bounded low-risk work items.
- The local edge worker executes each child task through Codex.
- Codex modifies only the allowed documentation path for that child task.
- The edge worker owns validation, commit, push and draft child PR creation.
- GitHub and CI policy decide whether a child PR may be auto-merged.
- The parent PR remains draft/manual while child PR behavior is observed.

## Acceptance Criteria

- Use compact lifecycle status updates that are safe to report back to SkyBridge.
- Do not reuse a dedupe key across lifecycle events or notification attempts.
- Create child PRs automatically for eligible subtasks.
- Gate child PR auto-merge through the configured strategy and CI policy.
- Keep the parent PR as draft/manual, with no unattended parent auto-merge.
- Keep each child task scoped to its declared file paths and safety boundaries.
- Avoid secrets, `.env` files, production config, deployment credentials, GitHub settings and server root configuration.

## Three-Round Safety Document Proof

Round 1 creates this lifecycle rerun note under `docs/dev/`. It proves the worker can carry a narrow docs-only task and publish a child PR without broader repository changes.

Round 2 should add or update a second docs-only proof note in `docs/dev/`, using a fresh task ID and fresh dedupe keys. It should confirm that repeated lifecycle events remain compact and non-duplicative.

Round 3 should add or update a final docs-only proof note in `docs/dev/`, again using a fresh task ID and fresh dedupe keys. It should confirm that child PR auto-merge remains strategy-gated while the parent PR stays draft/manual.

After all three rounds, the operator can compare Hermes task state, SkyBridge lifecycle events, notification attempts, GitHub child PR state and parent PR state to confirm the lifecycle path.

## Round 1 Task

Task `hermes-super-162-pr-20260526065837` is the first proof round. It must create this file only:

```text
docs/dev/super-162-lifecycle-rerun.md
```

This task is documentation-only. It must not change runtime code, tests, secrets, environment files, deployment paths, production configuration, GitHub settings or server root configuration. The nested Codex worker must not run `git add`, `git commit`, `git push` or `gh pr create`; the edge worker owns those lifecycle steps after validation passes.
