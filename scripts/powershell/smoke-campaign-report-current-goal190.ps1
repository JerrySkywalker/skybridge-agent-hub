$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$current = $result.report.current_step_summary
if ($result.report.current_goal_id -ne "super-190-campaign-run-report-evidence-ledger") { throw "Expected Goal 190 current goal." }
if ($result.report.current_goal_status -ne "ready") { throw "Expected Goal 190 ready." }
if ($result.report.current_goal_unexecuted -ne $true) { throw "Expected Goal 190 unexecuted." }
if (@($current.linked_task_ids).Count -ne 0) { throw "Expected Goal 190 linked task ids empty." }
if (@($current.linked_pr_urls).Count -ne 0) { throw "Expected Goal 190 linked PR URLs empty." }
if (@($result.report.blockers | Where-Object { $_ -match "historical" }).Count -gt 0) { throw "Historical findings must not be current blockers." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-current-goal190"; token_printed = $false } | ConvertTo-Json -Compress
