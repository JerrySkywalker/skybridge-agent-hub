# Codex TUI Master Goal Workflow

Codex TUI is the recommended interface for SkyBridge's primary autonomous development work. It gives the agent a durable Master Goal, lets Jerry supervise or redirect long-running work when needed, and keeps planning closer to the implementation context than the PowerShell queue runner can.

## When To Use It

Use Codex TUI for:

- multi-hour product goals;
- goals that need staged design, implementation, testing and documentation;
- work where Codex should inspect the repo, adapt the plan and make multiple commits;
- interactive supervision during Jerry's thesis-defense period.

Use the PowerShell `yolo-runner` only when a bounded Markdown goal is already ready for unattended batch processing. Use `codex exec` for scripted CI, repair or one-shot automation.

## Source Of Truth

The durable planning files are:

```text
goals/00_AUTONOMOUS_MASTER_GOAL.md
goals/mega/*.md
docs/dev/PROGRESS.md
```

`goals/00_MASTER_GOAL.md` remains the product-level vision. `goals/00_AUTONOMOUS_MASTER_GOAL.md` is the agent operating plan. `goals/mega/*.md` contains executable long-horizon goal plans.

## Starting A Mega Goal

From the repository root:

```powershell
codex
```

Then paste a prompt like:

```text
/goal Execute Mega Goal 001 from goals/mega/001-self-observable-skybridge-loop.md.

Read AGENTS.md, goals/00_AUTONOMOUS_MASTER_GOAL.md, docs/codex/TUI_MASTER_GOAL.md and the goal file first. Work one staged sub-goal at a time, make coherent commits, run focused checks before commits, run just check before stopping, push the branch, and do not cross the safety boundaries.
```

If `just` is unavailable, Codex should run `corepack pnpm check` and document the fallback.

## Session Loop

1. Read the Master Goal and active mega goal.
2. Restate the active stage and the smallest useful implementation slice.
3. Inspect only the files needed for that stage.
4. Edit, test and document the stage.
5. Commit the passing stage.
6. Log progress in `docs/dev/PROGRESS.md` and, when useful, the active mega goal.
7. Continue to the next stage until the goal is complete or blocked.

Keep the branch reviewable. Do not bundle unrelated product features into a planning or workflow goal.

## Progress Notes

Progress notes should include:

- date;
- active mega goal and stage;
- commits created;
- checks run and results;
- blockers, risks or deferred follow-ups.

Use concise entries. The progress log is for recovery and review, not for full terminal transcripts.

## Commit Expectations

Each stage should usually produce one commit. A stage may produce more commits when it naturally splits into reviewable parts such as schema, server behavior, UI and docs.

Recommended commit shape:

```text
feat(scope): implement focused behavior
test(scope): cover focused behavior
docs(scope): update workflow or operating notes
```

Do not squash the commits from an autonomous mega goal unless Jerry explicitly asks.

## Relationship To The Runner

The TUI Master Goal workflow is for primary development. The runner is a fallback batch processor:

- `goals/ready` is the runner queue.
- `goals/doing`, `goals/done` and `goals/failed` are runner state directories.
- `.agent/runs` stores ignored runtime logs.
- `MaxParallel` must stay `1`.

Do not move a mega goal into `goals/ready` directly. If a mega goal needs unattended runner work, extract a small bounded child goal and place only that child goal in `goals/ready`.

## Safety Boundaries

The TUI workflow inherits the repository safety rules:

- no secrets;
- no production deployment;
- no root-level server configuration changes;
- no destructive cleanup;
- no force-push to `main`;
- no authentication or authorization weakening;
- no runner parallelism;
- no default telemetry that uploads full command output or secrets.

When a stage would cross a boundary, stop that stage and record a follow-up task instead.
