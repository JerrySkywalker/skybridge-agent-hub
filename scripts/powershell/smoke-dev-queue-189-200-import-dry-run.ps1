$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" import -GoalPackDir (Join-Path $PSScriptRoot "..\..\goals\dev-queue-189-200") -DryRun -Json | ConvertFrom-Json
if (-not $result.validation.ok -or $result.would_import.goals.Count -ne 12) { throw "dev queue import dry-run failed" }
$result | ConvertTo-Json -Depth 10 -Compress
