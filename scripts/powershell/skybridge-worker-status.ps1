[CmdletBinding()]
param(
  [ValidateSet("status", "register", "heartbeat", "register-heartbeat")]
  [string]$Command = "status",
  [string]$ConfigFile,
  [string]$ProjectId,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$workerStatusCommand = $Command
$workerStatusConfigFile = $ConfigFile
$workerStatusProjectId = $ProjectId
$workerStatusJson = $Json

. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")
. (Join-Path $PSScriptRoot "load-worker-profile.ps1")

$Command = $workerStatusCommand
$ConfigFile = $workerStatusConfigFile
$ProjectId = $workerStatusProjectId
$Json = $workerStatusJson

function Write-WorkerStatusResult {
  param($Result)
  if ($Json) {
    $Result | ConvertTo-Json -Depth 20 -Compress
    return
  }
  "Worker:  $($Result.worker_id)"
  "Name:    $($Result.name)"
  "Project: $($Result.project_id)"
  "API:     $($Result.api_base)"
  "Auth:    $($Result.auth_mode)"
  if ($Result.profile_loaded) { "Profile: loaded" }
  if ($Result.registered -ne $null) { "Register: $($Result.registered)" }
  if ($Result.heartbeat -ne $null) { "Heartbeat: $($Result.heartbeat)" }
  if ($Result.remote_status) { "Status:  $($Result.remote_status)" }
  if ($Result.last_seen) { "Seen:    $($Result.last_seen)" }
  "TokenPrinted: false"
}

$profile = Read-WorkerProfile -Path $ConfigFile
$config = ConvertTo-EdgeWorkerConfig -Profile $profile -ProjectId $ProjectId
if ($config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $config))) {
  throw "SkyBridge worker token is required by the configured token_env_var or token_file."
}

$registered = $null
$heartbeat = $null
if ($Command -in @("register", "register-heartbeat")) {
  $registered = (Register-Worker -Config $config).ok
}
if ($Command -in @("heartbeat", "register-heartbeat")) {
  $heartbeat = (Send-WorkerHeartbeat -Config $config -StatusNote "operator_status").ok
}

$remoteWorker = $null
try {
  $remoteWorker = (Invoke-SkyBridgeApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($config.worker_id))" -ApiBase $config.api_base -Config $config -TimeoutSeconds 10).worker
} catch {}

Write-WorkerStatusResult ([pscustomobject]@{
  ok = $true
  worker_id = $config.worker_id
  name = $config.name
  project_id = $config.project_id
  api_base = $config.api_base
  auth_mode = $config.auth_mode
  token_file_configured = -not [string]::IsNullOrWhiteSpace([string]$config.token_file)
  token_printed = $false
  profile_loaded = [bool]$config.profile_loaded
  registered = $registered
  heartbeat = $heartbeat
  remote_status = if ($remoteWorker -and $remoteWorker.status) { [string]$remoteWorker.status } else { $null }
  last_seen = if ($remoteWorker -and $remoteWorker.last_seen_at) { [string]$remoteWorker.last_seen_at } else { $null }
  current_task_id = if ($remoteWorker -and $remoteWorker.current_task_id) { [string]$remoteWorker.current_task_id } else { $null }
})
