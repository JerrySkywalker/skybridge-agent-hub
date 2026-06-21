# Task Hygiene Repair Preview

Goal 316 adds `skybridge-task-hygiene-repair-preview.ps1` to turn the Goal 315
task hygiene buckets into an operator-readable preview plan. It is preview-only
and does not mutate task state.

The script consumes the current `skybridge.task_hygiene_report.v1` output, or
recomputes it through `skybridge-task-hygiene-report.ps1`, then emits
`skybridge.task_hygiene_repair_preview.v1`.

## Run

```powershell
. "$HOME\.skybridge\skybridge.env.ps1"

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-repair-preview.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -Json
```

Optional output file:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-repair-preview.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -OutputFile .agent\tmp\task-hygiene-repair-preview.json `
  -Json
```

## Preview Buckets

`remote-docs-exec-pilot-001` is classified as
`evidence-repair-only`. A future apply goal may write evidence metadata for
the existing task and related PR only. It must not create a new PR, requeue,
rerun Codex or claim the task.

These tasks are previewed as keep-blocked vs archive decision candidates:

```text
always-on-worker-loop-pilot-docs-179
task_proposal-59a0236fb69800cd
remote-claim-smoke-001
```

They are not execution candidates. A future apply goal would need to record the
operator decision, reason code, timestamp and explicit no-requeue/no-execution
evidence.

The eleven unsafe-to-requeue tasks are listed as
`excluded_from_requeue`. They must remain out of worker scheduling until a
separate explicit recovery policy proves a safe path. Goal 317 can record this
exclusion as hygiene metadata, but it still must not requeue or schedule them.

Goal 317 adds `skybridge-task-hygiene-apply.ps1` as the controlled
preview/apply follow-up. Its default mode is preview. Live apply is not run
during PR validation because it mutates live task metadata; the operator may
run it only after merge with the exact confirmation string documented in
[TASK_HYGIENE_APPLY.md](TASK_HYGIENE_APPLY.md).

## Safety

The preview reports these safety fields:

```text
preview_only=true
tasks_mutated=false
tasks_claimed=false
tasks_requeued=false
tasks_cancelled=false
tasks_archived=false
evidence_written=false
codex_run_called=false
queue_apply_called=false
project_control_unpaused=false
start_one_called=false
run_until_hold_called=false
token_printed=false
```

It excludes logs, prompts, Hermes responses, notification payloads, tokens,
cookies, credentials and environment dumps.

## Smoke

```powershell
corepack pnpm smoke:task-hygiene-repair-preview
```

The smoke is fixture-only. It verifies one evidence-repair-only task, three
archive-or-keep-blocked tasks, eleven unsafe-to-requeue exclusions and no
mutation-class safety flags.
