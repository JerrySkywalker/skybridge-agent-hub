[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$output = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1") -FixtureMissingManualTaskRoute -Json 2>$null
$exitCode = $LASTEXITCODE
$report = $output | ConvertFrom-Json
if ($exitCode -eq 0) { throw "Expected parity checker to fail when manual-task route is missing." }
if ($report.deployment_parity_status -ne "server_online_but_outdated") { throw "Expected server_online_but_outdated." }
if ($report.recommended_action -ne "Cloud server online but outdated; deploy server >= v2.4.") { throw "Expected outdated warning." }
if ($Json) { $report | ConvertTo-Json -Depth 8 -Compress } else { $report | Format-List }
