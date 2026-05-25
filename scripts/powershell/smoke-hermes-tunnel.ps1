[CmdletBinding()]
param(
  [switch]$CheckOnly,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$arguments = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\start-hermes-tunnel.ps1",
  "-CheckOnly",
  "-Json"
)

$output = & pwsh @arguments
$exitCode = $LASTEXITCODE
$result = ($output -join "`n") | ConvertFrom-Json

$summary = [ordered]@{
  ok = ($exitCode -eq 0)
  check_only = $true
  tunnel_listening = [bool]$result.listening
  matching_processes = [int]$result.matching_processes
  hermes_api_key_value_included = $false
  result = $result
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 10
} else {
  Write-Host "[smoke-hermes-tunnel] listening=$($summary.tunnel_listening) processes=$($summary.matching_processes)"
  if (-not $summary.tunnel_listening) {
    Write-Host "[smoke-hermes-tunnel] tunnel is not active; this is recoverable with start-hermes-tunnel.ps1 -Start or -Restart"
  }
}

exit 0
