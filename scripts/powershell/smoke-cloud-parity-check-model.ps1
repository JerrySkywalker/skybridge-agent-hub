[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$report = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1") -FixtureHealthy -Json | ConvertFrom-Json
if (-not $report.ok -or $report.deployment_parity_status -ne "ok") { throw "Expected healthy fixture parity ok." }
if ($report.token_printed -ne $false) { throw "Expected token_printed=false." }
if ($Json) { $report | ConvertTo-Json -Depth 8 -Compress } else { $report | Format-List }
