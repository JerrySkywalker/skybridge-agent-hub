[CmdletBinding()]
param(
  [string]$ServiceName = "SkyBridgeWorkerService",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [string[]]$ForceMissingTool = @(),
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Resolve-SkyBridgeRepoRoot {
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    return (Resolve-Path -LiteralPath $RepoRoot).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-SkyBridgeHomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    return (Resolve-Path -LiteralPath $HomeRoot).Path
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
  return "."
}

function Test-SkyBridgeCommand {
  param([string]$Name)
  try { return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue) } catch { return $false }
}

function Test-SkyBridgeConfigKey {
  param([string]$Path, [string[]]$Keys)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $text = Get-Content -Raw -LiteralPath $Path
  foreach ($key in $Keys) {
    if ($text -match ("(?m)^\s*(?:\`$env:)?{0}\s*=" -f [regex]::Escape($key))) { return $true }
  }
  return $false
}

function Read-SkyBridgeSafeConfigValue {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($text, ("(?m)^\s*(?:\`$env:)?{0}\s*=\s*['""]?([^'""]+)" -f [regex]::Escape($Key)))
  if (-not $match.Success) { return $null }
  $value = $match.Groups[1].Value.Trim()
  if ($value -notmatch "^[A-Za-z0-9_.:@-]{1,80}$") { return $null }
  return $value
}

function Read-SkyBridgeSafeApiBaseHost {
  param([string]$Path)
  $candidate = $env:SKYBRIDGE_API_BASE
  if ([string]::IsNullOrWhiteSpace($candidate)) { $candidate = $env:SKYBRIDGE_REMOTE_API_BASE }
  if ([string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $text = Get-Content -Raw -LiteralPath $Path
    $match = [regex]::Match($text, "(?m)^\s*(?:\`$env:)?(?:SKYBRIDGE_API_BASE|SKYBRIDGE_REMOTE_API_BASE)\s*=\s*['""]?([^'""]+)")
    if ($match.Success) { $candidate = $match.Groups[1].Value.Trim() }
  }
  if ([string]::IsNullOrWhiteSpace($candidate)) { return $null }
  try {
    $uri = [Uri]$candidate
    if ([string]::IsNullOrWhiteSpace($uri.Host)) { return $null }
    return $uri.Host
  } catch {
    return "configured_unparsed"
  }
}

function Read-SkyBridgeWorkerServiceState {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try {
    $raw = Get-Content -Raw -LiteralPath $Path
    if ($raw -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|token_printed`"\s*:\s*true") {
      return [pscustomobject]@{
        state_read_error = "unsafe_state_metadata_detected"
      }
    }
    return $raw | ConvertFrom-Json
  } catch {
    return [pscustomobject]@{
      state_read_error = "state_metadata_unreadable"
    }
  }
}

function Get-SkyBridgeServiceSnapshot {
  param([string]$Name)
  if (-not $IsWindows) {
    return [pscustomobject]@{
      service_installed = $false
      service_running = $false
      service_start_type = "unsupported_non_windows"
      warning = "windows_service_inspection_unavailable"
    }
  }

  try {
    $service = Get-CimInstance -ClassName Win32_Service -Filter ("Name='{0}'" -f $Name.Replace("'", "''")) -ErrorAction Stop
    if (-not $service) {
      return [pscustomobject]@{
        service_installed = $false
        service_running = $false
        service_start_type = "not_installed"
        warning = $null
      }
    }
    return [pscustomobject]@{
      service_installed = $true
      service_running = ([string]$service.State -eq "Running")
      service_start_type = if ([string]::IsNullOrWhiteSpace([string]$service.StartMode)) { "unknown" } else { [string]$service.StartMode }
      warning = $null
    }
  } catch {
    return [pscustomobject]@{
      service_installed = $false
      service_running = $false
      service_start_type = "unknown"
      warning = "service_inspection_failed"
    }
  }
}

$repo = Resolve-SkyBridgeRepoRoot
$homeRootPath = Resolve-SkyBridgeHomeRoot
$skybridgeConfig = Join-Path $homeRootPath ".skybridge\skybridge.env.ps1"
$workerConfig = Join-Path $homeRootPath ".skybridge\worker.env.ps1"
$workerToken = Join-Path $homeRootPath ".skybridge\worker-token.txt"
$stateDir = Join-Path $homeRootPath ".skybridge\state"
$serviceStatePath = Join-Path $stateDir "worker-service.json"
$workerHeartbeatScript = Join-Path $homeRootPath ".skybridge\worker-heartbeat.ps1"
$serviceState = Read-SkyBridgeWorkerServiceState -Path $serviceStatePath

$repoRootDetected = (
  (Test-Path -LiteralPath (Join-Path $repo "package.json") -PathType Leaf) -and
  (Test-Path -LiteralPath (Join-Path $repo "AGENTS.md") -PathType Leaf)
)

$apiBaseConfigured = (
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_API_BASE) -or
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_REMOTE_API_BASE) -or
  (Test-SkyBridgeConfigKey -Path $skybridgeConfig -Keys @("SKYBRIDGE_API_BASE", "SKYBRIDGE_REMOTE_API_BASE"))
)

$tokenFilePresent = (
  (Test-Path -LiteralPath $workerToken -PathType Leaf) -or
  (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_TOKEN_FILE) -and (Test-Path -LiteralPath $env:SKYBRIDGE_WORKER_TOKEN_FILE -PathType Leaf))
)

$configuredWorkerId = $env:SKYBRIDGE_WORKER_ID
if ([string]::IsNullOrWhiteSpace($configuredWorkerId)) {
  $configuredWorkerId = Read-SkyBridgeSafeConfigValue -Path $workerConfig -Key "SKYBRIDGE_WORKER_ID"
}
$workerIdConfigured = -not [string]::IsNullOrWhiteSpace($configuredWorkerId)
$workerId = if ($workerIdConfigured) { $configuredWorkerId } else { "local-windows-worker" }

$repoRootConfigured = (
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_REPO_ROOT) -or
  (Test-SkyBridgeConfigKey -Path $workerConfig -Keys @("SKYBRIDGE_REPO_ROOT"))
)
$serviceNameConfigured = (
  -not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_SERVICE_NAME) -or
  (Test-SkyBridgeConfigKey -Path $workerConfig -Keys @("SKYBRIDGE_WORKER_SERVICE_NAME"))
)
$apiBaseHost = Read-SkyBridgeSafeApiBaseHost -Path $skybridgeConfig
$stateServiceInstalled = $serviceState -and [bool]($serviceState.service_installed)
$stateServiceRunning = $serviceState -and [bool]($serviceState.service_running)
$stateLastHeartbeatAt = if ($serviceState -and $serviceState.PSObject.Properties.Name -contains "last_heartbeat_at") {
  if ($serviceState.last_heartbeat_at -is [DateTime]) {
    $serviceState.last_heartbeat_at.ToUniversalTime().ToString("o")
  } else {
    [string]$serviceState.last_heartbeat_at
  }
} else { $null }
$stateCloudRegistered = $serviceState -and [bool]($serviceState.cloud_worker_registered)
$stateCloudStatus = if ($serviceState -and $serviceState.PSObject.Properties.Name -contains "cloud_worker_status") { [string]$serviceState.cloud_worker_status } else { "unknown" }
$stateInstallStrategy = if ($serviceState -and $serviceState.PSObject.Properties.Name -contains "install_strategy") { [string]$serviceState.install_strategy } else { "not_installed" }

$tools = [ordered]@{
  powershell = $true
  git = Test-SkyBridgeCommand "git"
  gh = Test-SkyBridgeCommand "gh"
  node = Test-SkyBridgeCommand "node"
  pnpm = (Test-SkyBridgeCommand "pnpm") -or (Test-SkyBridgeCommand "corepack")
  codex = Test-SkyBridgeCommand "codex"
  matlab = (Test-SkyBridgeCommand "matlab") -or (Test-SkyBridgeCommand "matlab.exe")
}
foreach ($toolName in @($ForceMissingTool)) {
  $normalizedTool = ([string]$toolName).Trim().ToLowerInvariant()
  if (@($tools.Keys) -contains $normalizedTool) { $tools[$normalizedTool] = $false }
}

$service = Get-SkyBridgeServiceSnapshot -Name $ServiceName
if (-not [bool]$service.service_installed -and $stateServiceInstalled) {
  $service = [pscustomobject]@{
    service_installed = $true
    service_running = $stateServiceRunning
    service_start_type = $stateInstallStrategy
    warning = $null
  }
}
$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not [bool]$service.service_installed) { $blockers.Add("service_not_installed") | Out-Null }
if ([bool]$service.service_installed -and -not [bool]$service.service_running) { $warnings.Add("service_installed_not_running") | Out-Null }
if (-not $apiBaseConfigured) { $blockers.Add("api_base_not_configured") | Out-Null }
if (-not $tokenFilePresent) { $blockers.Add("worker_token_file_missing") | Out-Null }
if (-not $repoRootDetected) { $blockers.Add("repo_root_not_detected") | Out-Null }
if (-not $workerIdConfigured) { $warnings.Add("worker_id_defaulted") | Out-Null }
if (-not $repoRootConfigured) { $warnings.Add("repo_root_detected_but_not_configured") | Out-Null }
if (-not $serviceNameConfigured) { $warnings.Add("service_name_defaulted") | Out-Null }
foreach ($requiredTool in @("powershell", "git", "node", "pnpm")) {
  if (-not [bool]$tools[$requiredTool]) { $blockers.Add("tool_missing_$requiredTool") | Out-Null }
}
if (-not [bool]$tools["gh"]) { $warnings.Add("gh_missing_pr_operations_disabled") | Out-Null }
if (-not [bool]$tools["codex"]) { $warnings.Add("codex_missing_codex_templates_disabled") | Out-Null }
if (-not [bool]$tools["matlab"]) { $warnings.Add("matlab_missing_matlab_templates_disabled") | Out-Null }
if (-not [string]::IsNullOrWhiteSpace([string]$service.warning)) { $warnings.Add([string]$service.warning) | Out-Null }
if ($serviceState -and $serviceState.PSObject.Properties.Name -contains "state_read_error") { $warnings.Add([string]$serviceState.state_read_error) | Out-Null }

$readinessStatus = if ($blockers.Count -gt 0) { "blocked" } elseif ($warnings.Count -gt 0) { "warning" } else { "ready" }
$recommended = if (-not [bool]$service.service_installed) {
  "run_install_preview"
} elseif (-not $apiBaseConfigured) {
  "create_skybridge_api_base_config"
} elseif (-not $tokenFilePresent) {
  "add_worker_token_file"
} elseif (-not $stateCloudRegistered) {
  "run_heartbeat_pairing_preview"
} elseif ($blockers.Count -gt 0) {
  "resolve_blockers"
} elseif ($warnings.Count -gt 0) {
  "review_capability_warnings"
} else {
  "ready_for_future_worker_loop_goal"
}

$report = [pscustomobject]@{
  schema = "skybridge.local_worker_service_status.v1"
  ok = $true
  worker_id = $workerId
  service_name = $ServiceName
  service_installed = [bool]$service.service_installed
  service_running = [bool]$service.service_running
  service_start_type = [string]$service.service_start_type
  install_strategy = $stateInstallStrategy
  install_state = if ([bool]$service.service_installed) { "installed" } else { "not_installed_preview_available" }
  repair_state = if ([bool]$service.service_installed) { "repair_preview_available" } else { "install_required_before_repair" }
  install_preview_available = $true
  repair_preview_available = $true
  install_apply_available = $true
  repair_apply_available = $true
  heartbeat_preview_available = $true
  heartbeat_apply_available = $true
  api_base_configured = [bool]$apiBaseConfigured
  api_base_host = if ([string]::IsNullOrWhiteSpace($apiBaseHost)) { $null } else { $apiBaseHost }
  token_file_present = [bool]$tokenFilePresent
  worker_id_configured = [bool]$workerIdConfigured
  repo_root_configured = [bool]$repoRootConfigured
  repo_root_detected = [bool]$repoRootDetected
  skybridge_config_path = $skybridgeConfig
  worker_config_path = $workerConfig
  worker_token_path = $workerToken
  service_state_path = $serviceStatePath
  service_command_preview = "pwsh -NoProfile -ExecutionPolicy Bypass -File $workerHeartbeatScript -Command heartbeat-preview"
  last_heartbeat_at = if ([string]::IsNullOrWhiteSpace($stateLastHeartbeatAt)) { $null } else { $stateLastHeartbeatAt }
  cloud_worker_registered = [bool]$stateCloudRegistered
  cloud_worker_status = $stateCloudStatus
  powershell_available = [bool]$tools["powershell"]
  git_available = [bool]$tools["git"]
  gh_available = [bool]$tools["gh"]
  node_available = [bool]$tools["node"]
  pnpm_available = [bool]$tools["pnpm"]
  codex_available = [bool]$tools["codex"]
  matlab_available = [bool]$tools["matlab"]
  capabilities = [pscustomobject]@{
    status_readonly = $true
    install_preview = $true
    repair_preview = $true
    doctor_readonly = $true
    service_apply = $true
    repair_apply = $true
    heartbeat_pairing = $true
    heartbeat_apply = $true
    task_claim = $false
    task_execute = $false
    template_runner = $false
    worker_loop = $false
    codex_execution = $false
    matlab_execution = $false
    arbitrary_shell = $false
    tools = [pscustomobject]$tools
    token_printed = $false
  }
  readiness_status = $readinessStatus
  blockers = @($blockers)
  warnings = @($warnings)
  recommended_next_action = $recommended
  claim_enabled = $false
  execute_enabled = $false
  template_runner_enabled = $false
  worker_loop_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 20 -Compress
} else {
  "Schema: $($report.schema)"
  "Worker: $($report.worker_id)"
  "Service: $($report.service_name)"
  "Installed: $($report.service_installed)"
  "Running: $($report.service_running)"
  "Readiness: $($report.readiness_status)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
