$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$goal189 = @($result.report.step_ledger | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" })[0]
if (-not $goal189) { throw "Expected Goal 189 in step ledger." }
if ($goal189.status -ne "completed") { throw "Expected Goal 189 completed." }
if ($goal189.recovered -ne $true) { throw "Expected Goal 189 recovered." }
if (@($goal189.linked_pr_urls).Count -lt 1) { throw "Expected Goal 189 PR evidence." }
if (@($result.report.recovery_ledger | Where-Object { $_.goal_id -eq $goal189.goal_id }).Count -lt 1) { throw "Expected recovery ledger entries for Goal 189." }
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-recovered-evidence"; token_printed = $false } | ConvertTo-Json -Compress
