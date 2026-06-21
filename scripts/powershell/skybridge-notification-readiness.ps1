[CmdletBinding()]
param(
  [switch]$Json,
  [switch]$DryRun,
  [string]$ApiBase,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureProvidersFile
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

$dryRunMode = $true
$providersRaw = @()
$summaryRaw = $null
$available = $false
if ($FixtureProvidersFile) {
  $fixture = Read-JsonFile -Path $FixtureProvidersFile
  $providersRaw = @((Get-Prop -Object $fixture -Name "providers" -Default @()) | Where-Object { $null -ne $_ })
  $summaryRaw = Get-Prop -Object $fixture -Name "summary"
  $available = $true
} else {
  $resolved = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
  Assert-SkybridgeApiBaseUsable -ApiBase $resolved
  Assert-SkybridgeApiBaseService -ApiBase $resolved -TimeoutSeconds $TimeoutSeconds | Out-Null
  $providers = Invoke-RestMethod -Method GET -Uri "$($resolved.TrimEnd('/'))/v1/notifications/providers" -TimeoutSec $TimeoutSeconds
  $providersRaw = @((Get-Prop -Object $providers -Name "providers" -Default @()) | Where-Object { $null -ne $_ })
  try { $summaryRaw = Invoke-RestMethod -Method GET -Uri "$($resolved.TrimEnd('/'))/v1/notifications/summary" -TimeoutSec $TimeoutSeconds } catch {}
  $available = $true
}

$readyStatuses = @("ok", "ready", "configured", "enabled", "active", "sent")
$providersOut = @($providersRaw | ForEach-Object {
  $status = [string](Get-Prop -Object $_ -Name "status" -Default "unknown")
  [pscustomobject]@{
    provider = [string](Get-Prop -Object $_ -Name "provider" -Default (Get-Prop -Object $_ -Name "name" -Default "unknown"))
    status = $status
    ready = ($readyStatuses -contains $status.ToLowerInvariant())
    configured = [bool](Get-Prop -Object $_ -Name "configured" -Default ($readyStatuses -contains $status.ToLowerInvariant()))
    dry_run_checked = $dryRunMode
    credential_values_exposed = [bool](Get-Prop -Object $_ -Name "credential_values_exposed" -Default $false)
    raw_notification_payload_included = $false
  }
})

$readyCount = @($providersOut | Where-Object { $_.ready }).Count
$credentialExposed = @($providersOut | Where-Object { $_.credential_values_exposed }).Count -gt 0
$status = if (-not $available -or $providersOut.Count -eq 0) { "not_ready" } elseif ($readyCount -gt 0) { if ($readyCount -eq $providersOut.Count) { "ready" } else { "partial" } } else { "not_ready" }

$report = [pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = (-not $credentialExposed)
  status = $status
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  dry_run = $true
  providers = @($providersOut)
  provider_count = $providersOut.Count
  ready_provider_count = $readyCount
  blocker_notice_supported = ($readyCount -gt 0)
  summary_available = ($null -ne $summaryRaw)
  real_send_performed = $false
  raw_notification_payload_included = $false
  credential_values_exposed = $credentialExposed
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20
} else {
  "Schema:       $($report.schema)"
  "Status:       $($report.status)"
  "DryRun:       true"
  "Providers:    ready=$($report.ready_provider_count) total=$($report.provider_count)"
  "CanNotice:    $($report.blocker_notice_supported)"
  "TokenPrinted: false"
}
