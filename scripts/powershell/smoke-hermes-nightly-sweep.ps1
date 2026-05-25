[CmdletBinding()]
param(
  [switch]$DryRun,
  [switch]$Json,
  [switch]$EnableAutoMerge,
  [switch]$Send,
  [string]$PolicyFile
)

$ErrorActionPreference = "Stop"

$arguments = @(
  "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
  "-File", ".\scripts\powershell\skybridge-hermes-supervisor.ps1",
  "-Mode", "NightlySweep",
  "-UseHermesApi",
  "-Json"
)
if ($DryRun) { $arguments += "-DryRun" }
if ($EnableAutoMerge) { $arguments += "-EnableAutoMerge" }
if ($Send) { $arguments += "-Send" }
if (-not [string]::IsNullOrWhiteSpace($PolicyFile)) { $arguments += @("-PolicyFile", $PolicyFile) }

$output = & pwsh @arguments
$exitCode = $LASTEXITCODE
$parsed = $null
try {
  $parsed = (($output) -join "`n") | ConvertFrom-Json
} catch {
  $parsed = $null
}

$sweep = @($parsed.actions | Where-Object { $_.label -eq "nightly_sweep" } | Select-Object -First 1)
$summary = [ordered]@{
  ok = ($exitCode -eq 0 -and $null -ne $parsed)
  dry_run = [bool]$DryRun
  enable_auto_merge_requested = [bool]$EnableAutoMerge
  send_requested = [bool]$Send
  policy_counts = if ($sweep.Count -gt 0 -and $sweep[0].json) { $sweep[0].json.policy_counts } else { $null }
  supervisor = $parsed
  raw_output_included = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 24
} else {
  Write-Host "[hermes-nightly-sweep] ok=$($summary.ok) auto_merge=$($summary.enable_auto_merge_requested) send=$($summary.send_requested)"
}

if (-not $summary.ok) {
  exit 1
}
