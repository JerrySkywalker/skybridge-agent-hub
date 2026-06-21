# Task Hygiene Apply

Goal 317 adds `skybridge-task-hygiene-apply.ps1` as the controlled follow-up to
Goal 315/316 task hygiene reporting. The default mode is preview. Apply is a
metadata-only operator action and is not part of PR validation.

## Boundary

The script must not claim, requeue or execute tasks. It must not call Codex,
`start-one`, `run-until-hold`, queue apply or unpause `project_control`.

Apply requires all of these:

- `-Apply`
- `-Confirm I_UNDERSTAND_GOAL_317_HYGIENE_METADATA_ONLY`
- the fixed Goal 316 candidate set
- before and after snapshots with execution gates still closed

During Goal 317 PR development, run preview only:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-task-hygiene-apply.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -Preview `
  -Json
```

## Fixed Task IDs

The only evidence repair task is:

```text
remote-docs-exec-pilot-001
```

The only blocked historical keep/archive candidates are:

```text
always-on-worker-loop-pilot-docs-179
task_proposal-59a0236fb69800cd
remote-claim-smoke-001
```

Unsafe-to-requeue tasks remain excluded from scheduling. Goal 317 records that
classification only; it does not turn any task into a retry candidate.

## Apply Semantics

Allowed metadata-only writes:

- repair recovered evidence metadata for `remote-docs-exec-pilot-001`;
- record that no new PR was created and no requeue/rerun occurred;
- mark blocked historical tasks as keep-blocked or archived by operator policy;
- mark unsafe-to-requeue tasks as excluded from requeue and worker scheduling.

Forbidden writes:

- status changes to `queued`, `claimed` or `running`;
- worker assignment or lease changes;
- claim creation;
- requeue;
- Codex execution;
- project control unpause.

## Smoke

```powershell
corepack pnpm smoke:task-hygiene-apply
```

The smoke uses a temporary SQLite server. It covers preview default behavior,
missing-confirmation failure, unexpected task-id rejection, forbidden status
transition rejection, fixture metadata-only apply, no task claim, no requeue,
no Codex execution, paused project control and `token_printed=false`.
