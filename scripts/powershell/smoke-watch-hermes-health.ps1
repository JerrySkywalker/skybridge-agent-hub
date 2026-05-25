[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\watch-hermes-health.ps1" -Once -Json
$exitCode = $LASTEXITCODE
$result = ($output -join "`n") | ConvertFrom-Json

$summary = [ordered]@{
  ok = ($exitCode -eq 0)
  health_ok = [bool]$result.ok
  status = $result.status
  send_requested = $false
  hermes_api_key_value_included = $false
  result = $result
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 18
} else {
  Write-Host "[smoke-watch-hermes-health] status=$($summary.status) health_ok=$($summary.health_ok)"
}

exit 0
