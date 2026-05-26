# Goal Registry Runbook

The Goal Registry is the server-side durable registry of objectives. Tasks are execution slices linked to goals; evidence and task progress update the goal, but task completion does not automatically complete the parent goal.

## Goal Fields

Goals support these registry fields:

- `goal_id`
- `project_id`
- `title`
- `description`
- `source`
- `priority`
- `risk`
- `status`
- `lifecycle`
- `acceptance_criteria`
- `evidence_requirements`
- `dedupe_key`
- `supersedes`
- `superseded_by`
- `stale_reason`
- `blocked_reason`
- `planner_metadata`
- `model_backend_metadata`
- `completion_note`
- `evidence_summary`
- `progress_summary`

`model_backend_metadata` is optional audit metadata for planner/executor adapters. It is not a core dependency and must not carry credentials.

## Lifecycle

Supported goal statuses:

```text
draft
ready
queued
active
partially_completed
completed
failed
blocked
superseded
archived
paused
cancelled
```

Governance rules:

- archived goals cannot receive new executable tasks;
- superseded goals cannot receive new executable tasks;
- blocked goals require `blocked_reason`;
- completed goals require `completion_note` or an evidence summary;
- superseded goals require `superseded_by` to reference an existing goal.

## Create And Inspect Goals

Create a project goal:

```powershell
Invoke-RestMethod -Method POST `
  -Uri http://127.0.0.1:8787/v1/projects/skybridge-agent-hub/goals `
  -ContentType application/json `
  -Body (@{
    goal_id = "docs-goal"
    title = "Update docs"
    source = "manual"
    priority = "medium"
    risk = "low"
    acceptance_criteria = @("runbook updated")
    evidence_requirements = @("validation command recorded")
  } | ConvertTo-Json -Depth 8)
```

Inspect goal detail:

```powershell
Invoke-RestMethod http://127.0.0.1:8787/v1/goals/docs-goal
```

Goal detail includes `task_summary`, `progress_summary` and the latest `evidence_summary` when task evidence exists.

## Import And Export Markdown

Import a Markdown goal:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\import-goal-markdown.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -ProjectId skybridge-agent-hub `
  -Path .\goals\ready\example.md `
  -Json
```

Export a server goal:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\export-goal-markdown.ps1 `
  -ApiBase http://127.0.0.1:8787 `
  -GoalId docs-goal `
  -OutFile .\goals\exported\docs-goal.md `
  -Json
```

The importer/exporter preserve title, summary, source metadata, priority/risk/status, dedupe key, acceptance criteria and evidence requirements. They do not read or write secrets.

## Task And Evidence Relationship

Tasks link to goals with `goal_id`. Completing a task can include an `evidence_summary`:

```json
{
  "summary": "Task completed safely.",
  "evidence_summary": {
    "task_id": "task-1",
    "goal_id": "docs-goal",
    "pr_url": "https://github.com/example/repo/pull/1",
    "commit_sha": "abc123",
    "changed_files": ["docs/example.md"],
    "validation_status": "passed",
    "ci_status": "not_run",
    "risk_status": "low",
    "summary": "Docs updated and smoke passed."
  }
}
```

SkyBridge updates task counts and evidence count on the goal. An active goal with completed task evidence becomes `partially_completed`; the operator or planner must explicitly complete the goal with evidence or a completion note.

## Smoke Tests

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-goal-registry.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-goal-import-export.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-goal-task-evidence.ps1
```
