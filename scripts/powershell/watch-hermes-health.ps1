[CmdletBinding()]
param(
  [switch]$Once,
  [switch]$Loop,
  [int]$IntervalSeconds = 60,
  [int]$MaxFailures = 3,
  [switch]$SendOnFailure,
  [string]$HermesApiBase,
  [string]$HermesApiKey,
  [switch]$Json,
  [int]$TimeoutSeconds = 8
)

$ErrorActionPreference = "Stop"

$bootstrapEnvLoader = Join-Path $PSScriptRoot "load-bootstrap-env.ps1"
if (Test-Path -LiteralPath $bootstrapEnvLoader -PathType Leaf) {
  . $bootstrapEnvLoader
}

$hermesEnvLoader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
if (Test-Path -LiteralPath $hermesEnvLoader -PathType Leaf) {
  . $hermesEnvLoader
}

if ([string]::IsNullOrWhiteSpace($HermesApiBase)) {
  $HermesApiBase = $env:HERMES_API_BASE
}
if ([string]::IsNullOrWhiteSpace($HermesApiKey)) {
  $HermesApiKey = $env:HERMES_API_KEY
}
if (-not $Loop) {
  $Once = $true
}

function Get-HermesEndpoint {
  param([string]$ApiBase)

  if ([string]::IsNullOrWhiteSpace($ApiBase)) {
    return [pscustomobject]@{ host = "127.0.0.1"; port = 18642; local = $true }
  }

  try {
    $uri = [System.Uri]$ApiBase
    $port = if ($uri.IsDefaultPort) {
      if ($uri.Scheme -eq "https") { 443 } else { 80 }
    } else {
      $uri.Port
    }
    return [pscustomobject]@{
      host = $uri.Host
      port = $port
      local = ($uri.Host -in @("127.0.0.1", "localhost", "::1", "[::1]"))
    }
  } catch {
    return [pscustomobject]@{ host = "127.0.0.1"; port = 18642; local = $true }
  }
}

function Test-TcpPort {
  param([string]$HostName, [int]$Port)

  $client = [System.Net.Sockets.TcpClient]::new()
  try {
    $task = $client.ConnectAsync($HostName, $Port)
    $connected = $task.Wait(1000)
    return ($connected -and $client.Connected)
  } catch {
    return $false
  } finally {
    $client.Dispose()
  }
}

function New-HermesHeaders {
  param([string]$ApiKey)

  $headers = @{ Accept = "application/json" }
  if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $headers["Authorization"] = "Bearer $ApiKey"
  }
  return $headers
}

function Invoke-HermesHealthGet {
  param(
    [string]$Path,
    [string]$ApiBase,
    [hashtable]$Headers
  )

  if ([string]::IsNullOrWhiteSpace($ApiBase)) {
    return [ordered]@{
      path = $Path
      ok = $false
      status = "missing_base"
      body_included = $false
    }
  }

  try {
    $body = Invoke-RestMethod -Method Get -Uri "$($ApiBase.TrimEnd('/'))$Path" -Headers $Headers -TimeoutSec $TimeoutSeconds
    return [ordered]@{
      path = $Path
      ok = $true
      status = "ok"
      properties = @($body.PSObject.Properties | ForEach-Object { $_.Name })
      body_included = $false
    }
  } catch {
    $statusCode = $null
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
    }
    return [ordered]@{
      path = $Path
      ok = $false
      status = "failed"
      http_status = $statusCode
      error = $_.Exception.Message
      body_included = $false
    }
  }
}

function Invoke-BootstrapWarning {
  param([string]$Message)

  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title "SkyBridge Hermes health degraded" `
    -Message $Message `
    -Severity "warning" `
    -Send `
    -Json
  if ($LASTEXITCODE -ne 0) {
    return @{ ok = $false; send_requested = $true; error = "bootstrap_notification_failed"; raw_output_included = $false }
  }
  return (($output -join "`n") | ConvertFrom-Json)
}

function Invoke-HermesHealthCheck {
  $endpoint = Get-HermesEndpoint -ApiBase $HermesApiBase
  $portListening = if ($endpoint.local) { Test-TcpPort -HostName $endpoint.host -Port $endpoint.port } else { $null }
  $headers = New-HermesHeaders -ApiKey $HermesApiKey

  $requests = @(
    Invoke-HermesHealthGet -Path "/health" -ApiBase $HermesApiBase -Headers $headers
    Invoke-HermesHealthGet -Path "/v1/capabilities" -ApiBase $HermesApiBase -Headers $headers
  )
  $requiredFailures = @($requests | Where-Object { -not $_.ok })
  $baseConfigured = -not [string]::IsNullOrWhiteSpace($HermesApiBase)
  $keyPresent = -not [string]::IsNullOrWhiteSpace($HermesApiKey)

  $status = "healthy"
  if (-not $baseConfigured) {
    $status = "missing_base"
  } elseif (-not $keyPresent) {
    $status = "missing_key"
  } elseif ($endpoint.local -and -not $portListening) {
    $status = "tunnel_down"
  } elseif ($requiredFailures.Count -gt 0) {
    $status = "api_degraded"
  }

  return [ordered]@{
    ok = ($status -eq "healthy")
    status = $status
    checked_at = (Get-Date).ToUniversalTime().ToString("o")
    hermes_api_base_configured = $baseConfigured
    hermes_api_base = if ($baseConfigured) { $HermesApiBase } else { $null }
    hermes_api_key_present = $keyPresent
    hermes_api_key_value_included = $false
    tunnel = [ordered]@{
      checked = [bool]$endpoint.local
      host = $endpoint.host
      port = $endpoint.port
      listening = $portListening
    }
    requests = $requests
    raw_body_included = $false
  }
}

$checks = New-Object System.Collections.Generic.List[object]
$failureCount = 0
$notification = $null
$sentFailureWarning = $false

do {
  $check = Invoke-HermesHealthCheck
  $checks.Add([pscustomobject]$check) | Out-Null

  if ($check.ok) {
    $failureCount = 0
  } else {
    $failureCount += 1
    if ($SendOnFailure -and -not $sentFailureWarning -and $failureCount -ge $MaxFailures) {
      $notification = Invoke-BootstrapWarning -Message "Hermes health watchdog observed $failureCount consecutive failure(s): $($check.status)."
      $sentFailureWarning = $true
    }
  }

  if (-not $Loop) { break }
  if ($failureCount -ge $MaxFailures -and -not $SendOnFailure) { break }
  Start-Sleep -Seconds $IntervalSeconds
} while ($true)

$latest = $checks[$checks.Count - 1]
$summary = [ordered]@{
  ok = [bool]$latest.ok
  status = $latest.status
  once = [bool]$Once
  loop = [bool]$Loop
  interval_seconds = $IntervalSeconds
  max_failures = $MaxFailures
  failure_count = $failureCount
  send_on_failure = [bool]$SendOnFailure
  notification = $notification
  latest = $latest
  checks = @($checks.ToArray())
  hermes_api_key_value_included = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 16
} else {
  Write-Host "[hermes-health] status=$($summary.status) ok=$($summary.ok) failures=$failureCount"
  Write-Host "[hermes-health] tunnel=$($latest.tunnel.listening) health=$((@($latest.requests) | Where-Object { $_.path -eq '/health' } | Select-Object -First 1).status) capabilities=$((@($latest.requests) | Where-Object { $_.path -eq '/v1/capabilities' } | Select-Object -First 1).status)"
}

exit 0
