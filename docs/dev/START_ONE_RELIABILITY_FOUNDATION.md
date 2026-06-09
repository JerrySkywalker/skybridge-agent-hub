# Start-One Reliability Foundation

After `bootstrap-trial-201-task-001` opens its task PR, the bootstrap trial must hold in `held_waiting_human_pr_review`.

The reliability contract is read-only with respect to the task PR:

- detect the existing open task PR for `bootstrap-trial-201-task-001`;
- refuse another `start-one` claim while the task PR is open;
- refuse another sanitized executor apply while the task PR is open;
- summarize PR state, changed files and CI/check status without raw logs or annotations;
- emit/report `human_pr_review_required`;
- keep auto-merge disabled.

Safe report output is available through:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-bootstrap-trial-goal201.ps1 `
  -Command start-one-reliability-report -Json
```

With `-Apply`, it writes the ignored local report:

```text
.agent/tmp/bootstrap-trial-201-one-shot/trial-report.json
```

Operator guidance:

- review the task PR manually;
- if acceptable, merge the task PR manually;
- after merge, run a later goal to attach final evidence and mark the bootstrap trial completed;
- do not execute a second task.
