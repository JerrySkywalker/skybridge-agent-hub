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
  $isReady = ($readyStatuses -contains $status.ToLowerInvariant())
  [pscustomobject]@{
    provider = [string](Get-Prop -Object $_ -Name "provider" -Default (Get-Prop -Object $_ -Name "name" -Default "unknown"))
    status = $status
    readiness_kind = "real_provider"
    ready = $isReady
    configured = [bool](Get-Prop -Object $_ -Name "configured" -Default $isReady)
    dry_run_safe = $false
    real_send_capable = $isReady
    blocker_notice_supported = $isReady
    dry_run_checked = $dryRunMode
    credential_values_exposed = [bool](Get-Prop -Object $_ -Name "credential_values_exposed" -Default $false)
    raw_notification_payload_included = $false
  }
})

$realProviderCount = $providersOut.Count
$realReadyCount = @($providersOut | Where-Object { $_.ready }).Count
$bootstrapNotifierPath = Join-Path $PSScriptRoot "notify-bootstrap.ps1"
$bootstrapDryRunAvailable = ($dryRunMode -and (Test-Path -LiteralPath $bootstrapNotifierPath -PathType Leaf))
if ($bootstrapDryRunAvailable) {
  $providersOut += [pscustomobject]@{
    provider = "bootstrap-notifier"
    status = "dry_run_available"
    readiness_kind = "bootstrap_dry_run"
    ready = $true
    configured = $false
    dry_run_safe = $true
    real_send_capable = $false
    blocker_notice_supported = $true
    dry_run_checked = $true
    credential_values_exposed = $false
    raw_notification_payload_included = $false
  }
}

$readyCount = @($providersOut | Where-Object { $_.ready }).Count
$dryRunSafeCount = @($providersOut | Where-Object { $_.dry_run_safe -and $_.blocker_notice_supported }).Count
$credentialExposed = @($providersOut | Where-Object { $_.credential_values_exposed }).Count -gt 0
$providerConfigurationStatus = if ($realReadyCount -gt 0) {
  "real_provider_ready"
} elseif ($realProviderCount -gt 0 -and $bootstrapDryRunAvailable) {
  "real_provider_unavailable_bootstrap_dry_run_available"
} elseif ($realProviderCount -gt 0) {
  "real_provider_unavailable"
} elseif ($bootstrapDryRunAvailable) {
  "no_provider_configured_bootstrap_dry_run_available"
} else {
  "no_provider_configured"
}
$status = if (-not $available) {
  "not_ready"
} elseif ($realReadyCount -gt 0) {
  if ($realReadyCount -eq $realProviderCount) { "ready" } else { "partial" }
} elseif ($bootstrapDryRunAvailable) {
  "partial"
} else {
  "not_ready"
}

$report = [pscustomobject]@{
  schema = "skybridge.notification_readiness.v1"
  ok = (-not $credentialExposed)
  status = $status
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  dry_run = $true
  providers = @($providersOut)
  provider_count = $providersOut.Count
  ready_provider_count = $readyCount
  real_provider_count = $realProviderCount
  real_ready_provider_count = $realReadyCount
  dry_run_safe_provider_count = $dryRunSafeCount
  provider_configuration_status = $providerConfigurationStatus
  bootstrap_dry_run_available = $bootstrapDryRunAvailable
  blocker_notice_supported = (($realReadyCount -gt 0) -or ($dryRunSafeCount -gt 0))
  report_delivery_supported = (($realReadyCount -gt 0) -or ($dryRunSafeCount -gt 0))
  review_gate_supported = $true
  real_provider_configured = ($realReadyCount -gt 0)
  notification_delivery_mode = if ($realReadyCount -gt 0) { "real_provider_available_dry_run_default" } elseif ($bootstrapDryRunAvailable) { "bootstrap_dry_run_only" } else { "unavailable" }
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
