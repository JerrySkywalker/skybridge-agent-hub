[CmdletBinding()]
param([switch]$DryRun, [switch]$Json)

$ErrorActionPreference = "Stop"
$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-hermes-planner.ps1" -DryRun -Json
if ($LASTEXITCODE -ne 0) { throw "Hermes planner dry-run failed." }
$result = $output | ConvertFrom-Json
if ($result.decision.decision -ne "continue") { throw "Expected continue decision." }
if ($result.decision.task.task_type -ne "docs") { throw "Expected docs task." }
if ($result.hermes_api_key_value_included) { throw "Planner exposed Hermes API key." }
$summary = @{ ok = $true; decision = $result.decision.decision; task_type = $result.decision.task.task_type; dry_run = $true }
if ($Json) { $summary | ConvertTo-Json -Depth 8 } else { Write-Host "[smoke-hermes-planner] ok=$($summary.ok) decision=$($summary.decision)" }
