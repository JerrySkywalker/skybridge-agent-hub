# Hermes PlannerAdapter

Hermes is an optional SkyBridge planner adapter. SkyBridge Core stores neutral planner metadata on tasks, but it does not require Hermes to create, claim or complete tasks.

## Contract

Planner decisions use strict JSON:

```json
{
  "decision": "continue|repair|wait|stop|blocked",
  "reason": "...",
  "task": {
    "title": "...",
    "task_type": "docs",
    "risk": "low",
    "prompt": "...",
    "allowed_paths": ["docs/"],
    "blocked_paths": [".env", "config/*.secret.ps1", ".agent/", ".data/"],
    "validation": ["corepack pnpm check"],
    "dedupe_key": "docs/example-task",
    "expected_files": ["docs/example.md"],
    "depends_on": [],
    "advances_acceptance": "Explains how this task advances the goal.",
    "merge_strategy": "auto_pr_auto_merge"
  },
  "stop_criteria_status": ["..."]
}
```

`continue` and `repair` create work. `wait`, `stop` and `blocked` do not. The self-bootstrap pilot should stay docs-only unless a later reviewed goal explicitly expands the safety envelope.

Hermes receives compact state from `build-planner-compact-state.ps1` during real loops. It must read `completed_tasks`, `open_tasks`, `open_prs`, `locked_files`, `do_not_repeat` and `remaining_acceptance_status` before creating a task. It should return `wait` for pending PR dependencies, `stop` when acceptance is complete and `blocked` when only high-risk work remains.

## Task Mapping

Hermes decisions become normal SkyBridge tasks:

- `source`: `hermes-planner`
- `task_type`: copied from planner JSON
- `risk`: copied from planner JSON
- `body`: bounded task prompt
- `prompt_summary`: short safe summary
- `planner_metadata`: decision, reason, adapter, paths, validation and stop criteria
- `planner_metadata.dedupe_key`: stable task-intent key used to prevent duplicate work
- `planner_metadata.expected_files`: expected touched files for lock/overlap detection
- `planner_metadata.depends_on`: task IDs or PR numbers that should finish first
- `planner_metadata.advances_acceptance`: concise acceptance mapping
- `planner_metadata.merge_strategy`: `auto_pr_auto_merge`, `auto_pr_manual_merge` or `human_review`
- `raw_response_included`: `false`
- `secrets_included`: `false`

The server validates risk/source values, bounds string fields and redacts secret-like planner metadata. Raw Hermes responses and `HERMES_API_KEY` are never stored.

## Scripts

Planner dry run:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-planner.ps1 -DryRun -Json
```

Create a task from a real Hermes decision:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-planner.ps1 `
  -MasterGoalFile .\goals\master\self-bootstrap-smoke.md `
  -CreateTask `
  -Json
```

Evaluate a completed task:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-hermes-evaluate-result.ps1 `
  -TaskId <task-id> `
  -Json
```

## Security Boundaries

- Load Hermes configuration only from process env or `$HOME\.skybridge\hermes.env.ps1`.
- Do not print, store or commit `HERMES_API_KEY`.
- Keep Hermes behind a private loopback tunnel.
- Do not ask Hermes to mutate production config, secrets, GitHub settings or branch protection.
- Keep raw prompts, raw command output and patches out of server telemetry.

## Required Reports

Hermes reports should state the endpoint used, model name, runtime mode, planner mode, session continuity status and tool-execution status. For the current local tunnel path this is typically `/v1/responses`, the configured Hermes model alias, private loopback runtime, real/dry-run/fixture planner mode, no persistent session continuity unless explicitly added, and tool execution avoided in planner calls.
