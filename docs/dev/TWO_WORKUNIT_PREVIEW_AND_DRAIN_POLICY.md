# BOINC-like v1 Two-Workunit Preview and Drain Policy

SkyBridge BOINC-like v1 remains preview-only. The two-workunit model describes the next scheduler shape without creating workunits, creating tasks, claiming tasks, executing Codex, or opening task PRs.

## Preview Policy

- `max_workunits_preview=2`
- `max_apply_workunits=0`
- `apply_enabled=false`
- `run_apply_enabled=false`
- `multi_workunit_apply_enabled=false`
- `require_resource_gate=true`
- `require_human_review=true`
- `stop_on_pr_created=true`
- `stop_on_ci_failure=true`
- `stop_on_warning=true`
- `token_printed=false`

The preview contains exactly two low-risk docs/local-smoke workunit candidates:

1. `boinc-v1-preview-workunit-a` targets `docs/boinc-v1-preview-workunit-a.md`.
2. `boinc-v1-preview-workunit-b` targets `docs/boinc-v1-preview-workunit-b.md`.

Both entries are modeled as `preview_only_not_created`. They are not durable workunits and do not create queue tasks or claims.

## Serialization

Repo-mutating work is serialized for a single repository. Workunit B waits for workunit A to be completed and finalized before any future authorized apply path could consider B. Parallel mutation in `skybridge-agent-hub` remains disabled.

If any task PR or review hold is open, the preview reports `blocked_by_open_review`. If the resource gate fails, the preview may still render the plan, but the apply gate reports `blocked_by_resource_gate`.

## Drain And Pause Policy

The v1 drain/pause model is descriptive only:

- `drain_after_current=true`
- `pause_after_current=true`
- `pause_new_claims=true`
- `stop_on_pr_created=true`
- `stop_on_ci_failure=true`
- `stop_on_warning=true`
- `emergency_stop=preview_only`
- `operator_hold=preview_only`
- `resource_gate_hold=preview_only`
- `review_hold=preview_only`
- `token_printed=false`

No worker is started or stopped by these controls. No queue apply is enabled.

## Action Matrix

| Action | Behavior |
| --- | --- |
| `preview` | Read-only preview. |
| `pause` | Preview-only pause state. |
| `drain` | Preview-only drain state. |
| `resume_preview_only` | Preview-only resume planning. |
| `emergency_stop_preview` | Preview-only emergency stop modeling. |
| `apply_disabled` | Apply remains disabled. |

Every action is preview-only and has `apply_enabled=false`, `task_created=false`, `task_claimed=false`, and `worker_started=false`.

## Next Safe Action

The next safe action is to review the two-workunit preview and drain policy while keeping apply disabled.
