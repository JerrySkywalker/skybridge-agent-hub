# Task Hygiene Report

`skybridge-task-hygiene-report.ps1` is a read-only Goal 315 report for task
queue residue after a completed goal. It explains why self-bootstrap readiness
can still warn about failed, blocked or evidence-incomplete tasks even when the
cloud deployment and worker heartbeat proofs are healthy.

Goal 315 is intentionally read-only. The report must not execute tasks, claim
tasks, requeue tasks, cancel tasks, unpause project control, call queue apply,
advance campaign metadata, run Codex, or expose raw prompts/logs.

## Run

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"
. "$HOME\.skybridge\worker.env.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-report.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -Json
```

Useful options:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-report.ps1 `
  -ApiBase https://skybridge.example.com `
  -ProjectId skybridge-agent-hub `
  -Json
```

The script reads current task state through the same safe status path used by
`skybridge-status.ps1 -Hygiene -ShowLeases -ShowAll -Json`. It includes a task
summary, per-task residue classifications, claim/lease status, worker assignment
status, PR presence, evidence status and the next safe action. It does not
include task prompts, task bodies, raw logs, raw transcripts, raw Hermes
responses, cookies, credentials, tokens or environment dumps.

## Output Contract

The report emits:

```text
schema = skybridge.task_hygiene_report.v1
ok = true
project_id = string
total_tasks = number
failed_unrecovered = number
blocked = number
needs_evidence = number
stale_leases = number
stale_claims = number
safe_requeue_candidates = [...]
evidence_repair_candidates = [...]
archive_or_keep_blocked_candidates = [...]
unsafe_to_requeue_candidates = [...]
recommended_next_safe_action = string
token_printed = false
```

Safety evidence is included both at top level and under `safety`:

```text
read_only = true
tasks_mutated = false
tasks_claimed = false
tasks_requeued = false
tasks_cancelled = false
project_control_unpaused = false
queue_apply_called = false
campaign_metadata_advanced = false
codex_run_called = false
raw_logs_included = false
raw_prompts_included = false
token_printed = false
```

## Classification

`failed_unrecovered` means a failed task has no safe recovered evidence. Goal
315 classifies this as `unsafe-to-requeue` by default. A later goal may design a
bounded retry or manual recovery path, but this report does not retry it.

`blocked` means a task is already in a blocked state. High-risk task surfaces
such as production, deploy, secrets, GitHub settings, server-root config,
OpenResty, Authelia, 1Panel or `/opt/skybridge-agent-hub` are classified as
`blocked-by-policy`. Low-risk historical blocked tasks are classified as
`historical-residue` and can be kept blocked in the report.

`needs_evidence` means a failed task has a related PR but lacks recovered task
evidence. These are `evidence-repair-only` candidates. The safe later action is
to reconcile evidence for the existing task/PR, not to create a new task, claim
work, run Codex or open another PR.

`stale_leases` and `stale_claims` are `recoverable` residue only in the sense
that a later explicit recovery goal may preview and then apply a lease or claim
repair. Goal 315 does not release leases or alter claims.

## Goal 316 Boundary

Goal 316 adds a preview-only repair planner for these hygiene buckets. It may
propose one or more of these actions, still behind explicit preview/apply
gates:

- repair evidence for `evidence-repair-only` tasks;
- archive or keep historical blocked tasks after operator review;
- preview stale lease or claim recovery before any mutation;
- define a separate retry policy for failed tasks that are still
  `unsafe-to-requeue`.

Goal 316 preserves the hard boundaries around secrets, production
configuration, task execution and project-control state. It does not apply the
repair. Goal 317 is the earliest follow-up that may be allowed to write bounded
evidence metadata or record archive/keep-blocked decisions.

Run the preview:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-repair-preview.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -Json
```

## Smoke

Run the fixture-only smoke:

```powershell
corepack pnpm smoke:task-hygiene-report
```

The smoke starts a temporary local server/database, creates fixture failed,
blocked, needs-evidence, historical and stale-claim tasks, runs the report, and
verifies the task snapshot did not change. It also checks `token_printed=false`
and that raw prompt/log fixture markers are not included.
