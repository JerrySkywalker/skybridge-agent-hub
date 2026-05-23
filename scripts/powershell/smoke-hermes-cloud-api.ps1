[CmdletBinding()]
param(
  [string]$HermesApiBase,
  [string]$HermesApiKey,
  [switch]$DryRun,
  [switch]$Json,
  [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

$loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $loader -PathType Leaf) {
  . $loader
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $HermesApiBase = $env:HERMES_API_BASE
}
if ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $HermesApiKey = $env:HERMES_API_KEY
}

function New-HermesHeaders {
  param([string]$ApiKey)

  $headers = @{
    "Accept" = "application/json"
  }
  if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $headers["Authorization"] = "Bearer $ApiKey"
  }
  return $headers
}

function Invoke-HermesGet {
  param(
    [string]$ApiBase,
    [string]$Path,
    [hashtable]$Headers,
    [int]$TimeoutSeconds,
    [bool]$Optional
  )

  $uri = "$($ApiBase.TrimEnd('/'))$Path"
  try {
    $body = Invoke-RestMethod -Method Get -Uri $uri -Headers $Headers -TimeoutSec $TimeoutSeconds
    $properties = @()
    if ($null -ne $body) {
      $properties = @($body.PSObject.Properties | ForEach-Object { $_.Name })
    }
    return @{
      path = $Path
      ok = $true
      status = "ok"
      optional = $Optional
      properties = $properties
      body_included = $false
      error = $null
    }
  } catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    return @{
      path = $Path
      ok = $false
      status = if ($Optional) { "skipped_or_unavailable" } else { "degraded" }
      optional = $Optional
      http_status = $statusCode
      body_included = $false
      error = $_.Exception.Message
    }
  }
}

$summary = @{
  ok = $true
  dry_run = [bool]$DryRun
  hermes_api_base_configured = -not [string]::IsNullOrWhiteSpace($HermesApiBase)
  hermes_api_base = if ([string]::IsNullOrWhiteSpace($HermesApiBase)) { $null } else { $HermesApiBase }
  hermes_api_key_present = -not [string]::IsNullOrWhiteSpace($HermesApiKey)
  hermes_api_key_value_included = $false
  ssh_tunnel_likely = $false
  status = "unknown"
  requests = @()
  raw_body_included = $false
}

if (-not [string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $summary.ssh_tunnel_likely = ($HermesApiBase -match "127\.0\.0\.1|localhost|\[::1\]")
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $summary.ok = $false
  $summary.status = "missing_base"
} elseif ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $summary.ok = $false
  $summary.status = "missing_key"
} elseif ($DryRun) {
  $summary.status = "dry_run"
  $summary.requests = @(
    @{ path = "/health"; status = "dry_run"; optional = $false; body_included = $false },
    @{ path = "/health/detailed"; status = "dry_run"; optional = $true; body_included = $false },
    @{ path = "/v1/capabilities"; status = "dry_run"; optional = $false; body_included = $false },
    @{ path = "/v1/models"; status = "dry_run"; optional = $true; body_included = $false }
  )
} else {
  $headers = New-HermesHeaders -ApiKey $HermesApiKey
  $requests = @()
  $requests += Invoke-HermesGet -ApiBase $HermesApiBase -Path "/health" -Headers $headers -TimeoutSeconds $TimeoutSeconds -Optional $false
  $requests += Invoke-HermesGet -ApiBase $HermesApiBase -Path "/health/detailed" -Headers $headers -TimeoutSeconds $TimeoutSeconds -Optional $true
  $requests += Invoke-HermesGet -ApiBase $HermesApiBase -Path "/v1/capabilities" -Headers $headers -TimeoutSeconds $TimeoutSeconds -Optional $false
  $requests += Invoke-HermesGet -ApiBase $HermesApiBase -Path "/v1/models" -Headers $headers -TimeoutSeconds $TimeoutSeconds -Optional $true
  $summary.requests = $requests

  $requiredFailures = @($requests | Where-Object { -not $_.optional -and -not $_.ok })
  if ($requiredFailures.Count -gt 0) {
    $summary.ok = $false
    $summary.status = "degraded"
  } else {
    $summary.status = "connected"
  }
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 12
} else {
  Write-Host "[hermes-cloud-api] status=$($summary.status) base_configured=$($summary.hermes_api_base_configured) key_present=$($summary.hermes_api_key_present) dry_run=$($summary.dry_run)"
  foreach ($request in $summary.requests) {
    Write-Host "[hermes-cloud-api] $($request.path) $($request.status)"
  }
}

if (-not $summary.ok -and $summary.status -notin @("missing_key", "missing_base", "degraded")) {
  exit 1
}
