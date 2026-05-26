param(
  [string]$ProfilePath = ".\config\worker-profile.cloud.example.json",
  [string]$ApiBase = "https://skybridge.example.invalid",
  [string]$TokenEnvVar = "SKYBRIDGE_WORKER_TOKEN",
  [switch]$DryRun,
  [switch]$RunReal
)

$ErrorActionPreference = "Stop"

if (-not $DryRun -and -not $RunReal) {
  $DryRun = $true
}

$loader = Join-Path $PSScriptRoot "load-worker-profile.ps1"
$api = Join-Path $PSScriptRoot "skybridge-worker-api.ps1"
. $api

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-remote-profile-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
$tempProfile = Join-Path $tempDir "worker.remote.json"

try {
  $profile = Get-Content -Raw -LiteralPath $ProfilePath | ConvertFrom-Json
  $profile.skybridge_api_base = $ApiBase
  $profile.auth_mode = "bearer_token"
  $profile.token_env_var = $TokenEnvVar
  $profile.allow_remote_server = $true
  $profile.reject_insecure_http_for_remote = $true
  $profile | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempProfile -Encoding UTF8

  $raw = & pwsh -ExecutionPolicy Bypass -File $loader -ConfigFile $tempProfile -ProjectId skybridge-agent-hub -AsEdgeWorkerConfig -Json
  if ($LASTEXITCODE -ne 0) { throw "Worker profile loader failed." }
  $config = $raw | ConvertFrom-Json

  $tokenPresent = -not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($TokenEnvVar))
  if ($DryRun) {
    $missingTokenError = $null
    try { Assert-SkyBridgeWorkerApiSafety -Config $config } catch { $missingTokenError = $_.Exception.Message }
    if ($config.auth_mode -ne "bearer_token") { throw "Expected bearer_token auth mode." }
    if ($ApiBase -notmatch "^https://") { throw "Dry-run remote ApiBase must be HTTPS." }
    $tokenValue = [Environment]::GetEnvironmentVariable($TokenEnvVar)
    if ($missingTokenError -and -not [string]::IsNullOrWhiteSpace($tokenValue) -and $missingTokenError -match [regex]::Escape($tokenValue)) {
      throw "Dry-run error leaked token value."
    }
    [pscustomobject]@{
      DryRun = $true
      ApiBase = $config.api_base
      AuthMode = $config.auth_mode
      TokenEnvVar = $config.token_env_var
      TokenPresent = $tokenPresent
      TokenPrinted = $false
      RequestConstruction = "verified"
    } | Format-List
    return
  }

  Assert-SkyBridgeWorkerApiSafety -Config $config
  Invoke-SkyBridgeApi -Method GET -Path "/v1/health" -ApiBase $config.api_base -TimeoutSeconds 10 | Out-Null
  [pscustomobject]@{
    DryRun = $false
    ApiBase = $config.api_base
    AuthMode = $config.auth_mode
    TokenPresent = $tokenPresent
    HealthReachable = $true
    TokenPrinted = $false
  } | Format-List
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
