$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$current = $result.report.current_step_summary
$goal190 = @($result.report.step_ledger | Where-Object { $_.goal_id -eq "super-190-campaign-run-report-evidence-ledger" })[0]
if (-not $goal190) { throw "Expected Goal 190 in step ledger." }
if ($goal190.status -ne "completed") { throw "Expected Goal 190 completed after the report PR merge." }
if ($result.report.current_goal_id -ne "super-198-multi-project-support") { throw "Expected Goal 198 current goal after Goal 197 completion." }
if ($result.report.current_goal_status -ne "ready") { throw "Expected Goal 198 ready." }
if ($result.report.current_goal_unexecuted -ne $true) { throw "Expected Goal 198 unexecuted." }
if (@($current.linked_task_ids).Count -ne 0) { throw "Expected Goal 198 linked task ids empty." }
if (@($current.linked_pr_urls).Count -ne 0) { throw "Expected Goal 198 linked PR URLs empty." }
if ($current.evidence_status -ne "missing") { throw "Expected Goal 198 evidence to remain missing before this PR is attached." }
if (@($result.report.blockers | Where-Object { $_ -match "historical" }).Count -gt 0) { throw "Historical findings must not be current blockers." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-current-goal190"; token_printed = $false } | ConvertTo-Json -Compress
