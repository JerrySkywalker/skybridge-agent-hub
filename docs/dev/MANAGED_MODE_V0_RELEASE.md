# Managed Mode v0 Release

Managed Mode v0 is the current release boundary for SkyBridge Agent Hub autonomous local work.

## Achieved

- Controlled self-bootstrap v0 is complete.
- Managed Mode Pilot 208 completed one docs/local-smoke workunit and merged PR #140.
- Managed Mode Run 209 completed one repeatable one-at-a-time workunit and merged PR #144.
- The 209 finalizer completed on main through PR #145.
- No general bounded queue apply or multi-workunit queue apply is enabled.

## Completed Run Timeline

| Run | State | PR | Merge commit | Changed file |
| --- | --- | --- | --- | --- |
| `managed-mode-pilot-208` | completed | <https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140> | `347f38d2e630a44390957827bbda2f94e529f2a5` | `docs/managed-mode-pilot-orientation.md` |
| `managed-mode-run-209` | completed | <https://github.com/JerrySkywalker/skybridge-agent-hub/pull/144> | `d04edabebbb4255748bcad0e54aca63f74793587` | `docs/managed-mode-repeatability-orientation.md` |

Finalizer evidence stays local under `.agent/tmp/managed-mode-pilot-208/` and `.agent/tmp/managed-mode-run-209/`. The v0 report records hashes of the finalizer evidence files and keeps `token_printed=false`.

## Current Boundary

Managed Mode v0 means one-at-a-time work has been proven repeatable, but the default state remains no execution.

- `active_tasks=0`
- `stale_leases=0`
- `runner_lock=none`
- open managed-mode PR count must be `0`
- `general_bounded_queue_apply_enabled=false`
- `multi_workunit_queue_enabled=false`
- `no_next_execution_authorized=true`
- `token_printed=false`

## Why Not Full BOINC v1 Yet

The BOINC-style queue still needs explicit locking, conflict handling, resource gating, and review boundaries before multi-workunit apply is safe. Managed Mode v0 keeps the proven path narrow: one workunit, one task, one claim, one Codex execution, one PR, then stop.

## Future Authorization

Future one-at-a-time runs need an explicit goal that authorizes the run id and limits. Before any run apply, the operator must verify:

- Managed Mode v0 release readiness is true.
- The local resource enforcement gate passes.
- The selected task is low risk and docs-only or otherwise explicitly allowed.
- The task PR will remain open for human review.
- General bounded queue apply remains disabled.

## Validation

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-v0.ps1 -Command release-readiness -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-managed-mode-v0.ps1 -Command release-report -Json
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v0-status-contract.ps1
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\smoke-managed-mode-v0-safe-report.ps1
```

## Operator Checklist

- Confirm completed runs include `managed-mode-pilot-208` and `managed-mode-run-209`.
- Confirm no active task, stale lease, runner lock, or open managed-mode PR exists.
- Confirm the next action requires an explicit future goal.
- Confirm the local resource gate is required before run apply.
- Keep start-all, generic queue apply, resume apply, and worker loops disabled.
