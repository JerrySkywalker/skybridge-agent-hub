# BOINC v1 Controlled Trial 221

Goal 221 is the first post-release BOINC-like v1 controlled trial workunit after `v0.99.0-boinc-like-v1-controlled-release`.

- Trial id: `boinc-v1-controlled-trial-221`.
- Workunit id: `boinc-v1-controlled-trial-221-workunit-001`.
- Task id: `boinc-v1-controlled-trial-221-task-001`.
- Work type: one low-risk `docs/local-smoke` update targeting `docs/boinc-v1-controlled-trial-221.md`.
- Required gates: release, operator approval, local resource, supervisor/server preview status, failure budget, evidence retention, audit/redaction, and safe export.
- Execution remains local and bounded to one Codex worker execution, one workunit, one task, one claim, and one task PR.
- Generic bounded queue apply, remote execution, and arbitrary command dispatch remain disabled.
- `token_printed=false`.

Run safe previews:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-controlled-trial.ps1 -Command status
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-controlled-trial.ps1 -Command trial-apply-gate -AuthorizeGoal221
```

The real trial apply is only:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-controlled-trial.ps1 -Command trial-apply -AuthorizeGoal221
```

If a task PR is created, stop immediately. The task PR must remain open for human review and must not be auto-merged.
