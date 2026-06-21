# Start-One Preview

Goal 318 adds `skybridge-start-one-preview.ps1` to explain what a future
start-one apply would select without claiming or executing a task.

This is a read-only preview path. It must not call live `start-one`, call
`run-until-hold`, claim tasks, requeue tasks, run Codex, unpause
`project_control`, send real notifications or mutate production task state.

## Run

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
. "$HOME\.skybridge\worker.env.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-start-one-preview.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Json
```

The output schema is `skybridge.start_one_preview.v1`.

Important safety fields:

```text
preview_only=true
would_claim=false
would_run_codex=false
would_unpause_project_control=false
token_printed=false
```

## Selection Rules

The preview excludes failed tasks, blocked tasks, completed tasks,
`hygiene_metadata.excluded_from_worker_scheduling=true`, tasks marked
excluded from requeue, unsafe-to-requeue tasks, high-risk or production-facing
tasks, tasks with active lease conflicts, missing evidence or blocked hygiene
metadata, and tasks assigned to offline legacy workers.

Only queued, low-risk, safe-type tasks with no blocked hygiene metadata, no
unsafe-to-requeue classification, no active lease conflict and a worker
capability match can become preview candidates.

If no safe task exists, the script returns:

```text
status=no_safe_candidate
selected_candidate=null
would_claim=false
would_run_codex=false
```

## Residue Exclusion

Goal 318 specifically proves old residue remains out of execution:

- the 12 unsafe-to-requeue tasks are excluded;
- the 3 blocked historical tasks are excluded;
- `remote-docs-exec-pilot-001` is excluded after evidence repair metadata;
- no Goal 315 or Goal 317 residue becomes eligible for start-one.

These exclusions are not claims and not requeues. They are read-only
classification evidence for a later human-reviewed execution pilot.

## Goal 319 Requirements

A later Goal 319 start-one apply pilot would need a separate explicit
authorization. It should be limited to one safe queued low-risk task, prove the
second gate is configured, prevent duplicate claims and duplicate task PRs,
send only safe blocker notices, keep raw logs/prompts out of SkyBridge, and
stop at human review after the single task.

## Smoke

```powershell
corepack pnpm smoke:start-one-preview
```

The smoke is fixture-only. It verifies no claim, no Codex run, no
`project_control` unpause, exclusion of failed/blocked/hygiene-excluded and
unsafe-to-requeue tasks, safe `no_safe_candidate` behavior, and
`token_printed=false`.
