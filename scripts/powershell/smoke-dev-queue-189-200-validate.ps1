$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" validate-pack -GoalPackDir (Join-Path $PSScriptRoot "..\..\goals\dev-queue-189-200") -Json | ConvertFrom-Json
if (-not $result.validation.ok -or $result.validation.goal_count -ne 12) { throw "dev queue validation failed" }
$result | ConvertTo-Json -Depth 10 -Compress
