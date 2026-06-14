# Controlled Trial Human Review And Finalizer

The controlled trial finalizer is intentionally separated from task PR creation.

- `trial-finalizer-preview` reads safe metadata and reports `held_waiting_human_review_controlled_trial_221` while the task PR is open.
- `trial-finalizer-apply` refuses to run unless the task PR is already merged.
- The finalizer verifies one execution, one task, one task PR, human review, no auto-merge, no raw artifacts, and `token_printed=false`.
- Goal 221 must not run finalizer apply after creating the task PR.
- Goal 222 readiness is false until human review and finalizer evidence are complete.

Preview:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-controlled-trial.ps1 -Command trial-finalizer-preview
```

Apply only after human review has merged the task PR:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-boinc-v1-controlled-trial.ps1 -Command trial-finalizer-apply
```
