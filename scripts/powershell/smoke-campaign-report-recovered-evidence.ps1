$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$previous = $result.report.previous_step_summary
if (-not $previous) { throw "Expected previous step summary." }
if ($previous.goal_id -ne "super-189-ci-guardian-pr-finalizer-hardening") { throw "Expected Goal 189 as previous step." }
if ($previous.status -ne "completed") { throw "Expected Goal 189 completed." }
if ($previous.recovered -ne $true) { throw "Expected Goal 189 recovered." }
if (@($previous.linked_pr_urls).Count -lt 1) { throw "Expected Goal 189 PR evidence." }
if (@($result.report.recovery_ledger | Where-Object { $_.goal_id -eq $previous.goal_id }).Count -lt 1) { throw "Expected recovery ledger entries for Goal 189." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-recovered-evidence"; token_printed = $false } | ConvertTo-Json -Compress
