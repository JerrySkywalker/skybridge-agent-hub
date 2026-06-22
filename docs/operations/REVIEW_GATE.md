# Review Gate

Mega Goal 323 adds `skybridge-review-gate.ps1` for conservative operator
decision semantics.

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-review-gate.ps1 `
  -ApiBase $env:SKYBRIDGE_API_BASE `
  -TokenFile "$HOME\.skybridge\worker-token.txt" `
  -Json
```

The output schema is `skybridge.review_gate.v1`.

Gate statuses:

- `safe_to_continue_preview_only`: sanitized reports and previews may continue;
- `safe_to_continue_bounded`: bounded run may continue only with the existing
  max-task constraints and explicit confirmation;
- `needs_operator_review`: hold before any bounded apply;
- `blocked`: required report, notification, evidence or paused-control proof is
  unavailable;
- `failed_closed`: unbounded run or daemon behavior was detected.

The gate only allows bounded continuation when project control remains paused,
old residue remains excluded, evidence semantics are available, operator
reporting is available, notification dry-run report delivery is available, no
unsafe active task exists, bounded-loop constraints remain enforced, and no
unbounded or daemon path is enabled.

The gate never enables unbounded run-until-hold, daemon mode, global
`project_control` unpause, old task claim, old task requeue or production
deployment.
