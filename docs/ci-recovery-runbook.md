# CI Recovery Quick Reference

This runbook is for SkyBridge operators recovering low-risk task failures under
time pressure. It condenses the common patterns from
`docs/failed-task-patterns.md`; use that longer analysis only when this
quick path does not fit.

Do not upload raw command output, raw Codex JSONL, prompts, patches, secrets or
local runtime snapshots as evidence. Record only concise PR, CI, merge and file
metadata.

## Setup

Set these variables for the commands below:

```powershell
$ApiBase = "https://skybridge.example.invalid"
$ProjectId = "skybridge-agent-hub"
$TaskId = "task_proposal-example"
$WorkerId = "operator-recovery"
$TokenFile = "$HOME\.skybridge\worker.<hostname>.token"
$PrNumber = 73
$Repo = "JerrySkywalker/skybridge-agent-hub"
```

If using environment-based auth instead of a token file, replace
`-TokenFile $TokenFile` with `-TokenEnvVar SKYBRIDGE_WORKER_TOKEN`.

## 1. Triage The Task

Check the operator-facing status first:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TaskId $TaskId `
  -TokenFile $TokenFile
```

Use the JSON view when you need exact fields:

```powershell
$status = pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TaskId $TaskId `
  -TokenFile $TokenFile `
  -Json | ConvertFrom-Json

$task = $status.tasks[0]
$task | Select-Object task_id,raw_status,display_status,recovered,ci_status,pr_url,evidence
```

If `raw_status=failed` but `recovered=True` and PR evidence is complete, stop:
the task is already recovered. Do not requeue it.

## 2. Scenario: Merged After Pending Checks

Use this when CI Guardian marked a task failed while checks were still pending,
but the child PR later passed and merged.

Verify the PR state:

```powershell
gh pr view $PrNumber `
  --repo $Repo `
  --json number,url,state,mergedAt,mergeCommit,headRefName,baseRefName,files,statusCheckRollup
```

Confirm checks:

```powershell
gh pr checks $PrNumber --repo $Repo
```

The recovery is valid only when:

- the PR is merged;
- required checks passed before merge;
- changed files match the task scope, usually docs-only for this runbook;
- no evidence contains raw logs, secrets, prompts, patches or command output.

Create safe evidence values:

```powershell
$pr = gh pr view $PrNumber `
  --repo $Repo `
  --json url,mergedAt,mergeCommit,files | ConvertFrom-Json

$PrUrl = $pr.url
$MergeCommit = $pr.mergeCommit.oid
$ChangedFiles = @($pr.files | ForEach-Object { $_.path })
```

Manually mark the task as recovered:

```powershell
$token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
$headers = @{ Authorization = "Bearer $token" }

$body = @{
  worker_id = $WorkerId
  pr_url = $PrUrl
  evidence_summary = @{
    task_id = $TaskId
    pr_url = $PrUrl
    merge_commit = $MergeCommit
    changed_files = $ChangedFiles
    validation_status = "passed"
    ci_status = "passed_after_pending"
    risk_status = "low_docs_only"
    recovered = $true
    recovery_status = "merged_after_pending_checks"
    summary = "Recovered after the child PR merged with passing checks."
    created_at = (Get-Date).ToUniversalTime().ToString("o")
  }
}

Invoke-RestMethod `
  -Method Post `
  -Uri "$ApiBase/v1/tasks/$TaskId/evidence-repair" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body ($body | ConvertTo-Json -Depth 16)
```

Verify the repaired display:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-status.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TaskId $TaskId `
  -TokenFile $TokenFile
```

Expected result: raw status remains `failed` for audit, while evidence shows
`recovered` or `failed/recovered`.

## 3. Scenario: Missing Evidence

Use this when the task failed with no usable `evidence_summary`, no recovery
flag, no final CI classification or no child PR URL.

First decide whether a child PR exists:

```powershell
gh pr list `
  --repo $Repo `
  --state all `
  --search $TaskId `
  --json number,url,state,mergedAt,mergeCommit,title,files,statusCheckRollup
```

If a child PR exists and is merged with passing checks, use the
`merged_after_pending_checks` recovery procedure above.

If no child PR exists, classify the failed boundary in the task note or
follow-up summary. Common classes are:

- `codex_transport_eof`;
- `worker_auth_unavailable`;
- `route_missing`;
- `validation_failed`;
- `evidence_timeout`;
- `no_task_processed`.

Do not fabricate recovered evidence without PR, CI and merge proof.

## 4. Resubmit After Evidence Timeout

Use this path when the task failed because evidence timed out or the worker
stopped before packaging a PR, and the work still needs to run.

If the existing task payload is still valid and no child PR exists, requeue the
same task:

```powershell
$token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
$headers = @{ Authorization = "Bearer $token" }

Invoke-RestMethod `
  -Method Post `
  -Uri "$ApiBase/v1/tasks/$TaskId/requeue" `
  -Headers $headers `
  -ContentType "application/json" `
  -Body "{}"
```

Run exactly one bounded worker pass:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TaskId $TaskId `
  -WorkerProfile "$HOME\.skybridge\worker.<hostname>.json" `
  -TokenFile $TokenFile `
  -NoSubmit `
  -Apply
```

If the existing task payload is incomplete or unsafe to reuse, submit a
replacement task with a new id and explicit recovery criteria:

```powershell
$RetryTaskId = "$TaskId-rerun-$(Get-Date -Format yyyyMMddHHmmss)"

pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-submit.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -GoalId "ci-recovery" `
  -GoalTitle "CI recovery" `
  -TaskId $RetryTaskId `
  -TaskTitle "Retry evidence-timeout task $TaskId" `
  -TaskBody "Retry $TaskId after evidence_timeout. Expected output: child PR, passing validation, final CI status, changed_files and safe evidence summary only." `
  -Risk low `
  -RequiredCapabilities codex `
  -Source operator-recovery `
  -TokenFile $TokenFile `
  -EnsureProject `
  -EnsureGoal `
  -Apply
```

Then run one bounded worker pass for the replacement:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TaskId $RetryTaskId `
  -WorkerProfile "$HOME\.skybridge\worker.<hostname>.json" `
  -TokenFile $TokenFile `
  -NoSubmit `
  -Apply
```

## 5. Stop Conditions

Stop and escalate instead of repairing when:

- the PR is open, closed-unmerged or checks are still pending;
- changed files exceed the approved task scope;
- checks failed for a real code/test issue;
- the task would require secrets, production config, GitHub settings or server
  root configuration changes;
- evidence would require uploading raw command output, prompts, patches or
  secrets.

Before ending the recovery, confirm project control is paused:

```powershell
pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-control.ps1 `
  -Command pause `
  -ApiBase $ApiBase `
  -ProjectId $ProjectId `
  -TokenFile $TokenFile `
  -Json
```
