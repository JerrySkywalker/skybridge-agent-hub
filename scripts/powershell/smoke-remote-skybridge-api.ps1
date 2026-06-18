param(
  [string]$ApiBase,
  [string]$TokenEnvVar = "SKYBRIDGE_WORKER_TOKEN",
  [string]$TokenFile,
  [switch]$WorkerSmoke,
  [switch]$AuthFailureCheck,
  [switch]$DryRun,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Write-SmokeResult($Result) {
  if ($Json) { $Result | ConvertTo-Json -Depth 20 -Compress }
  else { $Result | Format-List }
}

function Get-WorkerToken {
  $token = [Environment]::GetEnvironmentVariable($TokenEnvVar)
  if ([string]::IsNullOrWhiteSpace($token) -and -not [string]::IsNullOrWhiteSpace($TokenFile)) {
    if (-not (Test-Path -LiteralPath $TokenFile -PathType Leaf)) {
      throw "TokenFile was provided but does not exist."
    }
    $token = (Get-Content -Raw -LiteralPath $TokenFile).Trim()
  }
  if ([string]::IsNullOrWhiteSpace($token)) { return $null }
  return $token
}

function Invoke-RemoteSkyBridge {
  param(
    [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    $Body = $null,
    [string]$Token
  )
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($Token)) {
    $headers["Authorization"] = "Bearer $Token"
  }
  $uri = "$($ApiBase.TrimEnd('/'))$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -TimeoutSec 20
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 12) -TimeoutSec 20
}

function Invoke-ExpectedAuthFailure {
  param([string]$Token, [string]$ExpectedPattern)
  try {
    Invoke-RemoteSkyBridge -Method POST -Path "/v1/workers/register" -Token $Token -Body @{
      worker_id = "remote-auth-failure-smoke"
      name = "Remote auth failure smoke"
      provider = "edge-worker"
      capabilities = @("docs")
    } | Out-Null
  } catch {
    $message = "$($_.Exception.Message) $($_.ErrorDetails.Message)"
    if ($message -notmatch $ExpectedPattern) {
      throw "Expected auth failure matching '$ExpectedPattern', got '$message'."
    }
    return $true
  }
  throw "Expected auth failure matching '$ExpectedPattern'."
}

if ([string]::IsNullOrWhiteSpace($ApiBase)) {
  $ApiBase = "https://skybridge.example.com"
  $DryRun = $true
}

if (-not $DryRun) {
  try {
    $uri = [System.Uri]::new($ApiBase)
    if ($uri.Scheme -ne "https" -and $uri.Host -notin @("127.0.0.1", "localhost", "::1")) {
      throw "Remote SkyBridge smoke requires HTTPS for non-localhost ApiBase."
    }
  } catch {
    throw "Invalid ApiBase '$ApiBase': $($_.Exception.Message)"
  }
}

$token = Get-WorkerToken

if ($DryRun) {
  Write-SmokeResult ([pscustomobject]@{
    DryRun = $true
    ApiBase = $ApiBase
    HealthCheck = "planned"
    WorkerSmoke = [bool]$WorkerSmoke
    AuthFailureCheck = [bool]$AuthFailureCheck
    TokenEnvVar = $TokenEnvVar
    TokenFileConfigured = -not [string]::IsNullOrWhiteSpace($TokenFile)
    TokenPresent = -not [string]::IsNullOrWhiteSpace($token)
    TokenPrinted = $false
  })
  return
}

$health = Invoke-RemoteSkyBridge -Method GET -Path "/v1/health"
$workerResult = $null
$authFailureResult = $null

if ($WorkerSmoke) {
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "WorkerSmoke requires a token from TokenEnvVar or TokenFile."
  }
  $workerId = "remote-smoke-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
  $registered = Invoke-RemoteSkyBridge -Method POST -Path "/v1/workers/register" -Token $token -Body @{
    worker_id = $workerId
    name = "Remote registration smoke"
    provider = "edge-worker"
    capabilities = @("docs", "tests")
    auth_mode = "bearer_token"
    api_base = $ApiBase
    allow_remote_server = $true
  }
  $heartbeat = Invoke-RemoteSkyBridge -Method POST -Path "/v1/workers/$([uri]::EscapeDataString($workerId))/heartbeat" -Token $token -Body @{
    status_note = "remote smoke heartbeat"
  }
  $workerResult = [pscustomobject]@{
    WorkerId = $workerId
    Registered = ($registered.worker.worker_id -eq $workerId)
    HeartbeatStatus = $heartbeat.worker.status
  }
}

if ($AuthFailureCheck) {
  $missingRejected = Invoke-ExpectedAuthFailure -Token "" -ExpectedPattern "missing_worker_token|Unauthorized|401"
  $wrongRejected = Invoke-ExpectedAuthFailure -Token "wrong-remote-smoke-token" -ExpectedPattern "invalid_worker_token|Forbidden|403"
  $authFailureResult = [pscustomobject]@{
    MissingTokenRejected = $missingRejected
    WrongTokenRejected = $wrongRejected
  }
}

Write-SmokeResult ([pscustomobject]@{
  DryRun = $false
  ApiBase = $ApiBase
  HealthOk = [bool]$health.ok
  Persistence = $health.persistence
  WorkerSmoke = $workerResult
  AuthFailureCheck = $authFailureResult
  TokenPrinted = $false
})
