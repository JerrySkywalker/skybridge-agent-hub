[CmdletBinding()]
param(
  [switch]$HeartbeatOnly,
  [string]$ConfigFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$WorkerId = "jerry-win-local-01",
  [string]$DisplayName,
  [string]$ApiBase,
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [int]$TimeoutSeconds = 15,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$workerHeartbeatProofJson = $Json
$workerHeartbeatProofConfigFile = $ConfigFile
$workerHeartbeatProofProjectId = $ProjectId
$workerHeartbeatProofWorkerId = $WorkerId
$workerHeartbeatProofDisplayName = $DisplayName
$workerHeartbeatProofApiBase = $ApiBase
$workerHeartbeatProofTokenEnvVar = $TokenEnvVar
$workerHeartbeatProofTokenFile = $TokenFile
$workerHeartbeatProofTimeoutSeconds = $TimeoutSeconds

. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")
. (Join-Path $PSScriptRoot "load-worker-profile.ps1")

$Json = $workerHeartbeatProofJson
$ConfigFile = $workerHeartbeatProofConfigFile
$ProjectId = $workerHeartbeatProofProjectId
$WorkerId = $workerHeartbeatProofWorkerId
$DisplayName = $workerHeartbeatProofDisplayName
$ApiBase = $workerHeartbeatProofApiBase
$TokenEnvVar = $workerHeartbeatProofTokenEnvVar
$TokenFile = $workerHeartbeatProofTokenFile
$TimeoutSeconds = $workerHeartbeatProofTimeoutSeconds

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function ConvertTo-SafeSummary {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
  $safe = $Text
  $safe = $safe -replace "(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9._-]+", "authorization=[redacted]"
  $safe = $safe -replace "(?i)bearer\s+[A-Za-z0-9._-]{12,}", "bearer [redacted]"
  $safe = $safe -replace "(?i)sk-[A-Za-z0-9_-]{20,}", "sk-[redacted]"
  $safe = $safe -replace "(?i)gh[pousr]_[A-Za-z0-9_]{20,}", "gh_[redacted]"
  $safe = $safe -replace "(?i)(token|secret|password|cookie|credential|api[_-]?key)\s*[:=]\s*\S+", '$1=[redacted]'
  $safe = $safe.Trim()
  if ($safe.Length -gt 220) { return $safe.Substring(0, 220) }
  return $safe
}

function New-BaseProof {
  param([bool]$Ok)
  [ordered]@{
    schema = "skybridge.worker_heartbeat_proof.v1"
    ok = $Ok
    worker_id = $WorkerId
    heartbeat_sent = $false
    worker_online_after = $false
    tasks_claimed = $false
    codex_run_called = $false
    queue_apply_called = $false
    campaign_metadata_advanced = $false
    start_one_called = $false
    run_until_hold_called = $false
    project_control_unpaused = $false
    token_printed = $false
  }
}

function Write-ProofResult {
  param($Result, [int]$ExitCode = 0)
  if ($Json) {
    [pscustomobject]$Result | ConvertTo-Json -Depth 20
  } else {
    [pscustomobject]$Result | Format-List
  }
  if ($ExitCode -ne 0) { exit $ExitCode }
}

if (-not $HeartbeatOnly) {
  $result = New-BaseProof -Ok $false
  $result["error"] = "heartbeat_only_ack_required"
  $result["required_flag"] = "-HeartbeatOnly"
  Write-ProofResult -Result $result -ExitCode 2
}

function New-DefaultHeartbeatConfig {
  $resolvedApiBase = if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { $ApiBase } else { $env:SKYBRIDGE_API_BASE }
  if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) {
    throw "SkyBridge API base is required. Pass -ApiBase or set SKYBRIDGE_API_BASE."
  }
  $resolvedName = if (-not [string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName } else { $WorkerId }
  [pscustomobject]@{
    worker_id = $WorkerId
    name = $resolvedName
    project_id = $ProjectId
    repo_path = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
    api_base = $resolvedApiBase
    auth_mode = if ($TokenEnvVar -or $TokenFile -or $env:SKYBRIDGE_WORKER_TOKEN -or $env:SKYBRIDGE_WORKER_TOKEN_FILE) { "bearer_token" } else { "none" }
    token_env_var = if ($TokenEnvVar) { $TokenEnvVar } else { "SKYBRIDGE_WORKER_TOKEN" }
    token_file = if ($TokenFile) { $TokenFile } else { $env:SKYBRIDGE_WORKER_TOKEN_FILE }
    allow_remote_server = $true
    reject_insecure_http_for_remote = $true
    capabilities = @("heartbeat", "codex", "docs", "windows")
    executor_adapters = @("codex")
    allowed_task_types = @("docs", "test")
    blocked_task_types = @("deploy", "production", "secrets")
    max_parallel_tasks = 1
    auto_merge_enabled = $false
    allow_production_deploy = $false
    notification_enabled = $false
    profile_loaded = $false
  }
}

function Resolve-HeartbeatConfig {
  if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
    $resolved = Resolve-Path -LiteralPath $ConfigFile -ErrorAction Stop
    $raw = Get-Content -Raw -LiteralPath $resolved.Path | ConvertFrom-Json
    $isWorkerProfile = (
      -not [string]::IsNullOrWhiteSpace([string]$raw.worker_id) -and
      $raw.project_ids -and
      $raw.repo_paths -and
      -not [string]::IsNullOrWhiteSpace([string]$raw.skybridge_api_base)
    )
    if ($isWorkerProfile) {
      $profile = Read-WorkerProfile -Path $resolved.Path
      $config = ConvertTo-EdgeWorkerConfig -Profile $profile -ProjectId $ProjectId
    } else {
      $config = Read-SkyBridgeWorkerConfig -ConfigFile $resolved.Path
    }
    if ($TokenEnvVar) { $config.token_env_var = $TokenEnvVar }
    if ($TokenFile) { $config.token_file = $TokenFile }
    return $config
  }
  return New-DefaultHeartbeatConfig
}

function Invoke-OptionalApi {
  param($Config, [string]$Method, [string]$Path)
  try {
    return Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $Config.api_base -Config $Config -TimeoutSeconds $TimeoutSeconds
  } catch {
    return [pscustomobject]@{
      available = $false
      error_summary = ConvertTo-SafeSummary -Text $_.Exception.Message
    }
  }
}

try {
  $config = Resolve-HeartbeatConfig
  $WorkerId = [string]$config.worker_id
  Assert-SkyBridgeWorkerApiSafety -Config $config

  $tasksBefore = Invoke-OptionalApi -Config $config -Method GET -Path "/v1/tasks/summary"
  $controlBefore = Invoke-OptionalApi -Config $config -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($config.project_id))/control"

  $registered = Register-Worker -Config $config -TimeoutSeconds $TimeoutSeconds
  $heartbeat = Send-WorkerHeartbeat -Config $config -StatusNote "heartbeat_only_proof" -Load 0 -TimeoutSeconds $TimeoutSeconds
  $workerAfter = Invoke-SkyBridgeApi -Method GET -Path "/v1/workers/$([uri]::EscapeDataString($config.worker_id))" -ApiBase $config.api_base -Config $config -TimeoutSeconds $TimeoutSeconds
  $workersSummary = Invoke-OptionalApi -Config $config -Method GET -Path "/v1/workers/summary"
  $tasksAfter = Invoke-OptionalApi -Config $config -Method GET -Path "/v1/tasks/summary"
  $controlAfter = Invoke-OptionalApi -Config $config -Method GET -Path "/v1/projects/$([uri]::EscapeDataString($config.project_id))/control"

  $workerStatus = [string](Get-Prop -Object $workerAfter.worker -Name "status" -Default "unknown")
  $onlineWorkerIds = @()
  try {
    $allWorkers = Invoke-SkyBridgeApi -Method GET -Path "/v1/workers" -ApiBase $config.api_base -Config $config -TimeoutSeconds $TimeoutSeconds
    $onlineWorkerIds = @($allWorkers.workers | Where-Object { [string](Get-Prop -Object $_ -Name "status") -eq "online" } | ForEach-Object { [string](Get-Prop -Object $_ -Name "worker_id") })
  } catch {}

  $projectStateBefore = [string](Get-Prop -Object (Get-Prop -Object $controlBefore -Name "control_state") -Name "state" -Default (Get-Prop -Object $controlBefore -Name "state"))
  $projectStateAfter = [string](Get-Prop -Object (Get-Prop -Object $controlAfter -Name "control_state") -Name "state" -Default (Get-Prop -Object $controlAfter -Name "state"))

  $result = New-BaseProof -Ok ($workerStatus -eq "online")
  $result["worker_id"] = [string]$config.worker_id
  $result["project_id"] = [string]$config.project_id
  $result["registered"] = [bool](Get-Prop -Object $registered -Name "ok" -Default $false)
  $result["heartbeat_sent"] = [bool](Get-Prop -Object $heartbeat -Name "ok" -Default $false)
  $result["worker_status_after"] = $workerStatus
  $result["worker_online_after"] = ($workerStatus -eq "online")
  $result["online_worker_ids"] = @($onlineWorkerIds)
  $result["workers"] = [pscustomobject]@{
    online = Get-Prop -Object $workersSummary -Name "online" -Default $null
    stale = Get-Prop -Object $workersSummary -Name "stale" -Default $null
    offline = Get-Prop -Object $workersSummary -Name "offline" -Default $null
  }
  $result["project_control"] = [pscustomobject]@{
    before = if ([string]::IsNullOrWhiteSpace($projectStateBefore)) { $null } else { $projectStateBefore }
    after = if ([string]::IsNullOrWhiteSpace($projectStateAfter)) { $null } else { $projectStateAfter }
  }
  $result["task_summary_before"] = [pscustomobject]@{
    queued = Get-Prop -Object $tasksBefore -Name "queued" -Default $null
    claimed = Get-Prop -Object $tasksBefore -Name "claimed" -Default $null
    running = Get-Prop -Object $tasksBefore -Name "running" -Default $null
  }
  $result["task_summary_after"] = [pscustomobject]@{
    queued = Get-Prop -Object $tasksAfter -Name "queued" -Default $null
    claimed = Get-Prop -Object $tasksAfter -Name "claimed" -Default $null
    running = Get-Prop -Object $tasksAfter -Name "running" -Default $null
  }
  $result["heartbeat_only"] = $true

  Write-ProofResult -Result $result
} catch {
  $result = New-BaseProof -Ok $false
  $result["error"] = "heartbeat_proof_failed"
  $result["error_summary"] = ConvertTo-SafeSummary -Text $_.Exception.Message
  Write-ProofResult -Result $result -ExitCode 1
}
