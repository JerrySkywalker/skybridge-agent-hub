# Codex Goal Mode for This Repository

This repository uses Markdown goals as the durable unit of AI work. Codex TUI plus Master Goal files are the recommended primary workflow for multi-hour development. The PowerShell runner remains available for queued batch/background goals.

For the TUI workflow, see `docs/codex/TUI_MASTER_GOAL.md`.

## Goal locations

```text
goals/ready   tasks ready to run
goals/doing   tasks currently being processed
goals/done    completed tasks
goals/failed  failed tasks
goals/backlog future tasks
goals/mega    long-horizon Codex TUI goals
```

`goals/ready`, `goals/doing`, `goals/done` and `goals/failed` are runner queue/state directories. They may be created by the runner when absent.

## Primary Codex TUI workflow

Start Codex TUI from the repository root:

```powershell
codex
```

Then execute a mega goal with a prompt such as:

```text
/goal Execute Mega Goal 001 from goals/mega/001-self-observable-skybridge-loop.md.

Read AGENTS.md, goals/00_AUTONOMOUS_MASTER_GOAL.md, docs/codex/TUI_MASTER_GOAL.md and the goal file first. Work one staged sub-goal at a time, make coherent commits, run focused checks before commits, run just check before stopping, push the branch, and do not cross the safety boundaries.
```

Use `goals/00_AUTONOMOUS_MASTER_GOAL.md` as the operating source of truth and `goals/00_MASTER_GOAL.md` as the product vision.

## Runner single goal fallback

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-goal.ps1 `
  -GoalFile .\goals\ready\001-yolo-guardrails.md
```

## Runner loop fallback

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -Mode ThesisYOLO `
  -MaxRepairRounds 3
```

For the full runner lifecycle, configuration and log layout, see `docs/codex/AUTONOMOUS_RUNNER.md`. Keep this path for bounded unattended work rather than primary long-horizon planning.

## Recommended pattern

- Make each goal small.
- Keep one vertical slice per goal.
- Define completion criteria.
- Define prohibited changes.
- Let Codex make implementation decisions within that boundary.

## Small-step Git iteration

- Split a goal into logical commits that each leave the repository in a passing state.
- Run the smallest relevant check before each commit, such as a package test or typecheck for the touched area.
- Commit after each coherent passing subtask; do not wait until the entire goal is complete.
- Do not squash the commits from an autonomous goal unless a human explicitly asks for it.
- Run `just check` before the final stop. If `just` is unavailable, run `corepack pnpm check` and document the fallback.
- Push the branch or `main` after the completed goal passes checks.

## Runner queue expectations

- Keep `MaxParallel` at `1` until the repository has explicit locking and conflict handling.
- Put only reviewable, bounded work in `goals/ready`.
- Prefer one vertical slice per goal file.
- Use `goals/backlog` for future work that needs human sequencing before it is safe for the runner.
