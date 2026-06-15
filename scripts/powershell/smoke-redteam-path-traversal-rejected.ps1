$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

function Test-PathTraversalRejected([string]$Candidate) {
  if ([string]::IsNullOrWhiteSpace($Candidate)) { return $true }
  if ($Candidate -match '(^|[\\/])\.\.([\\/]|$)') { return $true }
  if ($Candidate -match '^[a-zA-Z]:[\\/]') { return $true }
  if ($Candidate -match '^[\\/]{2}') { return $true }
  if ($Candidate -match '[\x00-\x1f]') { return $true }
  return $false
}

$cases = @(
  "..\outside",
  "../outside",
  "packages/../../outside",
  "C:\Windows\System32",
  "\\server\share\package"
)

foreach ($candidate in $cases) {
  if (-not (Test-PathTraversalRejected $candidate)) { throw "Path traversal candidate was not rejected." }
}

$hostConsent = Invoke-SmokeJson "skybridge-host-consent-preview.ps1" @("-Command", "consent-gate")
Assert-False $hostConsent.host_mutation_allowed "host_mutation_allowed"

Write-Host "[smoke-redteam-path-traversal-rejected] ok"
