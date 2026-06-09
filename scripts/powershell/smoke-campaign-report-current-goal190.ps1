$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$current = $result.report.current_step_summary
$goal190 = @($result.report.step_ledger | Where-Object { $_.goal_id -eq "super-190-campaign-run-report-evidence-ledger" })[0]
if (-not $goal190) { throw "Expected Goal 190 in step ledger." }
if ($goal190.status -ne "completed") { throw "Expected Goal 190 completed after the report PR merge." }
$goal200 = @($result.report.step_ledger | Where-Object { $_.goal_id -eq "super-200-controlled-goal-draft-review-import" })[0]
if (-not $goal200) { throw "Expected Goal 200 in step ledger." }
if ($result.report.current_goal_id -ne "super-200-controlled-goal-draft-review-import") { throw "Expected Goal 200 current goal after dev queue completion." }
if ($result.report.current_goal_status -ne "completed") { throw "Expected Goal 200 completed." }
if ($result.report.current_goal_unexecuted -ne $false) { throw "Expected Goal 200 executed/completed." }
if (@($current.linked_task_ids).Count -ne 0) { throw "Expected Goal 200 linked task ids empty." }
if (@($current.linked_pr_urls).Count -ne 1) { throw "Expected Goal 200 linked PR URL." }
if ($current.evidence_status -ne "present") { throw "Expected Goal 200 evidence to be present." }
if (@($result.report.blockers | Where-Object { $_ -match "historical" }).Count -gt 0) { throw "Historical findings must not be current blockers." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-current-goal190"; token_printed = $false } | ConvertTo-Json -Compress
