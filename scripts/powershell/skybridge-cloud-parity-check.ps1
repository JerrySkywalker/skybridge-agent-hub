[CmdletBinding()]
param(
  [string]$ApiBase,
  [switch]$Json,
  [switch]$FixtureMissingManualTaskRoute,
  [switch]$FixtureHealthy,
  [string]$FixtureVersionFile
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force

$ApiBase = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
$fixtureMode = ($FixtureHealthy -or $FixtureMissingManualTaskRoute -or -not [string]::IsNullOrWhiteSpace($FixtureVersionFile))
Assert-SkybridgeApiBaseUsable -ApiBase $ApiBase -AllowPlaceholder $fixtureMode

function Read-JsonFile {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "JSON fixture file not found."
  }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

if (-not $fixtureMode) {
  Assert-SkybridgeApiBaseService -ApiBase $ApiBase -TimeoutSeconds 20 | Out-Null
} elseif (-not [string]::IsNullOrWhiteSpace($FixtureVersionFile)) {
  Assert-SkybridgeVersionService -Version (Read-JsonFile -Path $FixtureVersionFile)
}

function Join-ApiRoute {
  param([string]$Base, [string]$Path)
  return ($Base.TrimEnd("/") + "/" + $Path.TrimStart("/"))
}

function New-RouteResult {
  param(
    [string]$Path,
    [string]$Method,
    [int]$StatusCode,
    [bool]$Ok,
    [string]$Error = ""
  )
  [pscustomobject]@{
    path = $Path
    method = $Method
    status_code = $StatusCode
    ok = $Ok
    error_summary = $Error
  }
}

function Invoke-ParityRoute {
  param(
    [string]$Path,
    [ValidateSet("GET", "POST")]
    [string]$Method
  )
  if ($FixtureHealthy) {
    return New-RouteResult -Path $Path -Method $Method -StatusCode 200 -Ok $true
  }
  if ($FixtureMissingManualTaskRoute) {
    if ($Path -eq "/v1/manual-tasks/providers") {
      return New-RouteResult -Path $Path -Method $Method -StatusCode 404 -Ok $false -Error "HTTP 404"
    }
    return New-RouteResult -Path $Path -Method $Method -StatusCode 200 -Ok $true
  }

  $uri = Join-ApiRoute -Base $ApiBase -Path $Path
  try {
    $parameters = @{
      Uri = $uri
      Method = $Method
      TimeoutSec = 15
      ErrorAction = "Stop"
    }
    if ($Method -eq "POST") {
      $parameters.ContentType = "application/json"
      $parameters.Body = (@{ question = "route parity smoke"; task_id = "route-parity-smoke" } | ConvertTo-Json -Compress)
    }
    $response = Invoke-WebRequest @parameters
    return New-RouteResult -Path $Path -Method $Method -StatusCode ([int]$response.StatusCode) -Ok ([int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300)
  } catch {
    $status = 0
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $status = [int]$_.Exception.Response.StatusCode
    }
    $message = ConvertTo-SkybridgeSafeText -Text $_.Exception.Message -MaxLength 180
    return New-RouteResult -Path $Path -Method $Method -StatusCode $status -Ok $false -Error $message
  }
}

$routes = @(
  @{ path = "/v1/health"; method = "GET" },
  @{ path = "/v1/version"; method = "GET" },
  @{ path = "/v1/summary"; method = "GET" },
  @{ path = "/v1/manual-tasks/providers"; method = "GET" },
  @{ path = "/v1/manual-tasks/run-next/mock"; method = "POST" }
)

$results = foreach ($route in $routes) {
  Invoke-ParityRoute -Path $route.path -Method $route.method
}

$healthOk = [bool](($results | Where-Object { $_.path -eq "/v1/health" } | Select-Object -First 1).ok)
$manualProviders = $results | Where-Object { $_.path -eq "/v1/manual-tasks/providers" } | Select-Object -First 1
$manualAvailable = [bool]($manualProviders.ok)
$missing = @($results | Where-Object { -not $_.ok } | ForEach-Object { $_.path })
$status = if ($missing.Count -eq 0) {
  "ok"
} elseif ($healthOk -and -not $manualAvailable) {
  "server_online_but_outdated"
} else {
  "failed"
}

$report = [pscustomobject]@{
  schema = "skybridge.cloud_route_parity.v1"
  api_base = "configured"
  status = $status
  ok = ($missing.Count -eq 0)
  server_online = $healthOk
  manual_task_routes_available = $manualAvailable
  deployment_parity_status = $status
  missing_routes = $missing
  routes = $results
  recommended_action = if ($status -eq "server_online_but_outdated") {
    "Cloud server online but outdated; deploy server >= v2.4."
  } elseif ($status -eq "ok") {
    "Cloud route parity ok."
  } else {
    "Cloud route parity failed; inspect route status and deploy report."
  }
  secrets_included = $false
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  $report | Format-List
}

if (-not $report.ok) {
  exit 1
}
