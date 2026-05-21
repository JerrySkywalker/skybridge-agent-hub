# Codex Goal Mode for This Repository

This repository uses Markdown goals as the primary unit of AI work.

## Goal locations

```text
goals/ready   tasks ready to run
goals/doing   tasks currently being processed
goals/done    completed tasks
goals/failed  failed tasks
goals/backlog future tasks
```

## Single goal

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\run-goal.ps1 `
  -GoalFile .\goals\ready\001-yolo-guardrails.md
```

## YOLO loop

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\yolo-runner.ps1 `
  -Mode ThesisYOLO `
  -MaxRepairRounds 3
```

## Recommended pattern

- Make each goal small.
- Keep one vertical slice per goal.
- Define completion criteria.
- Define prohibited changes.
- Let Codex make implementation decisions within that boundary.
