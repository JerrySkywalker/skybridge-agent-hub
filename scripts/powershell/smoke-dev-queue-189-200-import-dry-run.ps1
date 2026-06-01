[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
$goalPackDir = Resolve-Path (Join-Path $PSScriptRoot "..\..\goals\dev-queue-189-200")
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign.ps1" import -GoalPackDir $goalPackDir -DryRun -Json | ConvertFrom-Json
if (-not $result.ok -or $result.mode -ne "dry-run") { throw "Expected import dry-run result." }
if (-not $result.would_import -or @($result.would_import.goals).Count -ne 12) { throw "Expected 12 goals in import dry-run payload." }
if ($result.token_printed -ne $false) { throw "Expected token_printed=false." }

$summary = [pscustomobject]@{
  ok = $true
  mode = $result.mode
  campaign_id = $result.would_import.campaign_id
  goal_count = @($result.would_import.goals).Count
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
