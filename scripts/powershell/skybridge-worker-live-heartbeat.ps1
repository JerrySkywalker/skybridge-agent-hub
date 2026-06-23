param(
  [ValidateSet("status", "preview", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [string]$WorkerId = "",
  [string]$WorkerName = "Jerry Windows Local Worker",
  [string]$Provider = "local-windows",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$HeartbeatConfirmationText = "I_UNDERSTAND_REGISTER_AND_HEARTBEAT_WORKER_ONLY_NO_TASK_CLAIM"

function ConvertTo-SkyBridgeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 32
}

function Resolve-SkyBridgeRepoRoot {
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { return (Resolve-Path -LiteralPath $RepoRoot).Path }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-SkyBridgeHomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    if (Test-Path -LiteralPath $HomeRoot -PathType Container) { return (Resolve-Path -LiteralPath $HomeRoot).Path }
    return $HomeRoot
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
  return "."
}

function Read-ConfigValue {
  param([string]$Path, [string[]]$Keys)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  foreach ($key in $Keys) {
    $match = [regex]::Match($text, ("(?m)^\s*(?:\`$env:)?{0}\s*=\s*['""]?([^'""]+)" -f [regex]::Escape($key)))
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
  }
  return $null
}

function Get-SafeApiBaseHost {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
  try {
    $uri = [Uri]$Value
    if ([string]::IsNullOrWhiteSpace($uri.Host)) { return $null }
    return $uri.Host
  } catch {
    return "configured_unparsed"
  }
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return [bool]($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|token_printed`"\s*:\s*true|raw_stdout|raw_stderr|raw_prompt|raw_response|raw_logs")
}

function Test-SafeWorkerId {
  param([string]$Value)
  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match "^[A-Za-z0-9_.-]{3,80}$"
}

function Test-SafeText {
  param([string]$Value, [int]$MaxLength = 120)
  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le $MaxLength -and -not (Test-UnsafeText $Value) -and $Value -match "^[\p{L}\p{N} ._:@/\-]+$"
}

function Test-SkyBridgeCommand {
  param([string]$Name)
  try { return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue) } catch { return $false }
}

function Get-DetectedCapabilities {
  $capabilities = New-Object System.Collections.Generic.List[string]
  $capabilities.Add("windows") | Out-Null
  $capabilities.Add("powershell") | Out-Null
  foreach ($tool in @("git", "gh", "node", "pnpm")) {
    if (Test-SkyBridgeCommand $tool) { $capabilities.Add($tool) | Out-Null }
  }
  if (Test-SkyBridgeCommand "codex") { $capabilities.Add("codex") | Out-Null }
  if ((Test-SkyBridgeCommand "matlab") -or (Test-SkyBridgeCommand "matlab.exe")) { $capabilities.Add("matlab") | Out-Null }
  @($capabilities | Select-Object -Unique)
}

function Get-AuthHeaders {
  param([string]$Path)
  $headers = @{}
  if (-not [string]::IsNullOrWhiteSpace($Path) -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
    $token = (Get-Content -Raw -LiteralPath $Path).Trim()
    if (-not [string]::IsNullOrWhiteSpace($token)) {
      $headers["Authorization"] = "Bearer $token"
    }
  }
  return $headers
}

function Invoke-WorkerApi {
  param(
    [ValidateSet("GET", "POST")]
    [string]$Method,
    [string]$Path,
    $Body = $null,
    [string]$ResolvedApiBase,
    [string]$ResolvedTokenFile
  )
  $parameters = @{
    Method = $Method
    Uri = ($ResolvedApiBase.TrimEnd("/") + $Path)
    Headers = Get-AuthHeaders -Path $ResolvedTokenFile
    SkipHttpErrorCheck = $true
  }
  if ($null -ne $Body) {
    $parameters.ContentType = "application/json"
    $parameters.Body = ($Body | ConvertTo-Json -Depth 12)
  }
  $response = Invoke-WebRequest @parameters
  $content = ($response.Content | Out-String).Trim()
  if (Test-UnsafeText $content) {
    return [pscustomobject]@{
      status_code = [int]$response.StatusCode
      body = [pscustomobject]@{ ok = $false; error = "unsafe_response_redacted"; token_printed = $false }
    }
  }
  $body = if ([string]::IsNullOrWhiteSpace($content)) {
    [pscustomobject]@{ ok = $false; error = "empty_response"; token_printed = $false }
  } else {
    $content | ConvertFrom-Json
  }
  [pscustomobject]@{
    status_code = [int]$response.StatusCode
    body = $body
  }
}

function Invoke-WorkerServiceStatus {
  param([string]$ResolvedHome, [string]$ResolvedRepo)
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -HomeRoot $ResolvedHome -RepoRoot $ResolvedRepo -Json
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Update-WorkerServiceState {
  param(
    [string]$ResolvedHome,
    [string]$ResolvedRepo,
    [string]$ResolvedApiBase,
    [string]$Id,
    [string]$Name,
    [string]$ResolvedProvider,
    [string[]]$Capabilities,
    [string]$CloudStatus,
    [string]$HeartbeatAt
  )
  $stateDir = Join-Path $ResolvedHome ".skybridge\state"
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  $statePath = Join-Path $stateDir "worker-service.json"
  $existing = $null
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    try { $existing = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json } catch { $existing = $null }
  }
  $state = [ordered]@{
    schema = "skybridge.local_worker_service_state.v1"
    service_name = if ($existing -and $existing.service_name) { [string]$existing.service_name } else { "SkyBridgeWorkerService" }
    worker_id = $Id
    worker_name = $Name
    worker_provider = $ResolvedProvider
    worker_identity_configured = $true
    worker_capabilities = @($Capabilities)
    install_strategy = if ($existing -and $existing.install_strategy) { [string]$existing.install_strategy } else { "not_installed" }
    service_installed = if ($existing) { [bool]$existing.service_installed } else { $false }
    service_running = if ($existing) { [bool]$existing.service_running } else { $false }
    service_start_type = if ($existing -and $existing.service_start_type) { [string]$existing.service_start_type } else { "not_installed" }
    admin_required = $false
    wrapper_path = if ($existing -and $existing.wrapper_path) { [string]$existing.wrapper_path } else { Join-Path $ResolvedHome ".skybridge\worker-heartbeat.ps1" }
    repo_root = $ResolvedRepo
    api_base_host = Get-SafeApiBaseHost -Value $ResolvedApiBase
    cloud_worker_registered = $true
    cloud_worker_status = $CloudStatus
    last_heartbeat_at = $HeartbeatAt
    last_live_heartbeat_result = "registered_heartbeat_online"
    claim_enabled = $false
    execute_enabled = $false
    template_runner_enabled = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding UTF8
  $statePath
}

function New-LiveHeartbeatReport {
  param(
    [string]$Mode,
    [bool]$Ok,
    [string]$ReviewReason,
    [string]$RecommendedNextAction,
    [bool]$WouldMutateServer,
    [bool]$ServerMutationPerformed,
    [string[]]$Blockers,
    [string[]]$Warnings,
    $Status,
    [string]$Id,
    [string]$Name,
    [string]$ResolvedProvider,
    [string[]]$Capabilities,
    $RegisterResponse = $null,
    $HeartbeatResponse = $null,
    $WorkerResponse = $null,
    [string]$StatePath = ""
  )
  $workerStatus = "unknown"
  $lastHeartbeat = $null
  $cloudSeen = $false
  if ($WorkerResponse -and $WorkerResponse.body -and $WorkerResponse.body.worker) {
    $cloudSeen = $true
    $workerStatus = [string]$WorkerResponse.body.worker.status
    $lastHeartbeat = $WorkerResponse.body.worker.last_seen_at
  } elseif ($HeartbeatResponse -and $HeartbeatResponse.body -and $HeartbeatResponse.body.worker) {
    $cloudSeen = $true
    $workerStatus = [string]$HeartbeatResponse.body.worker.status
    $lastHeartbeat = $HeartbeatResponse.body.worker.last_seen_at
  }

  [pscustomobject]@{
    schema = "skybridge.worker_live_heartbeat.v1"
    ok = $Ok
    command = $Command
    mode = $Mode
    worker_id = if ([string]::IsNullOrWhiteSpace($Id)) { $null } else { $Id }
    worker_name = if ([string]::IsNullOrWhiteSpace($Name)) { $null } else { $Name }
    provider = if ([string]::IsNullOrWhiteSpace($ResolvedProvider)) { $null } else { $ResolvedProvider }
    capabilities = @($Capabilities)
    api_base_configured = -not [string]::IsNullOrWhiteSpace($resolvedApiBase)
    api_base_host = Get-SafeApiBaseHost -Value $resolvedApiBase
    token_file_present = -not [string]::IsNullOrWhiteSpace($resolvedTokenFile) -and (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf)
    token_value_printed = $false
    register_endpoint = "/v1/workers/register"
    heartbeat_endpoint = if ([string]::IsNullOrWhiteSpace($Id)) { $null } else { "/v1/workers/$Id/heartbeat" }
    worker_get_endpoint = if ([string]::IsNullOrWhiteSpace($Id)) { $null } else { "/v1/workers/$Id" }
    worker_registered = ($RegisterResponse -and $RegisterResponse.status_code -ge 200 -and $RegisterResponse.status_code -lt 300)
    heartbeat_sent = ($HeartbeatResponse -and $HeartbeatResponse.status_code -ge 200 -and $HeartbeatResponse.status_code -lt 300)
    cloud_worker_seen = $cloudSeen
    cloud_worker_status = $workerStatus
    last_heartbeat_at = $lastHeartbeat
    service_state_path = $StatePath
    status = $Status
    register_status_code = if ($RegisterResponse) { $RegisterResponse.status_code } else { $null }
    heartbeat_status_code = if ($HeartbeatResponse) { $HeartbeatResponse.status_code } else { $null }
    worker_get_status_code = if ($WorkerResponse) { $WorkerResponse.status_code } else { $null }
    review_reason = $ReviewReason
    blockers = @($Blockers)
    warnings = @($Warnings)
    recommended_next_action = $RecommendedNextAction
    would_mutate_server = $WouldMutateServer
    server_mutation_performed = $ServerMutationPerformed
    claim_enabled = $false
    execute_enabled = $false
    template_runner_enabled = $false
    claim_created = $false
    execution_started = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    task_claimed = $false
    notification_sent = $false
    token_printed = $false
  }
}

$resolvedRepo = Resolve-SkyBridgeRepoRoot
$resolvedHome = Resolve-SkyBridgeHomeRoot
$skybridgeConfig = Join-Path $resolvedHome ".skybridge\skybridge.env.ps1"
$workerConfig = Join-Path $resolvedHome ".skybridge\worker.env.ps1"
$resolvedApiBase = $ApiBase
if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) { $resolvedApiBase = $env:SKYBRIDGE_API_BASE }
if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) { $resolvedApiBase = $env:SKYBRIDGE_REMOTE_API_BASE }
if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) { $resolvedApiBase = Read-ConfigValue -Path $skybridgeConfig -Keys @("SKYBRIDGE_API_BASE", "SKYBRIDGE_REMOTE_API_BASE") }

$resolvedWorkerId = $WorkerId
if ([string]::IsNullOrWhiteSpace($resolvedWorkerId)) { $resolvedWorkerId = $env:SKYBRIDGE_WORKER_ID }
if ([string]::IsNullOrWhiteSpace($resolvedWorkerId)) { $resolvedWorkerId = Read-ConfigValue -Path $workerConfig -Keys @("SKYBRIDGE_WORKER_ID") }
$resolvedWorkerName = $WorkerName
if ([string]::IsNullOrWhiteSpace($resolvedWorkerName)) { $resolvedWorkerName = $env:SKYBRIDGE_WORKER_NAME }
if ([string]::IsNullOrWhiteSpace($resolvedWorkerName)) { $resolvedWorkerName = Read-ConfigValue -Path $workerConfig -Keys @("SKYBRIDGE_WORKER_NAME") }
$resolvedProvider = $Provider
if ([string]::IsNullOrWhiteSpace($resolvedProvider)) { $resolvedProvider = $env:SKYBRIDGE_WORKER_PROVIDER }
if ([string]::IsNullOrWhiteSpace($resolvedProvider)) { $resolvedProvider = Read-ConfigValue -Path $workerConfig -Keys @("SKYBRIDGE_WORKER_PROVIDER") }
$capabilities = Get-DetectedCapabilities

$resolvedTokenFile = $TokenFile
if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) { $resolvedTokenFile = $env:SKYBRIDGE_WORKER_TOKEN_FILE }
if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) { $resolvedTokenFile = Join-Path $resolvedHome ".skybridge\worker-token.txt" }

$status = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
if (-not (Test-SafeWorkerId $resolvedWorkerId)) { $blockers.Add("worker_id_not_configured") | Out-Null }
if (-not (Test-SafeText $resolvedWorkerName -MaxLength 120)) { $blockers.Add("worker_name_invalid_or_missing") | Out-Null }
if (-not (Test-SafeWorkerId $resolvedProvider)) { $blockers.Add("worker_provider_invalid_or_missing") | Out-Null }
if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) { $blockers.Add("api_base_not_configured") | Out-Null }
if (-not (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf)) { $blockers.Add("worker_token_file_missing") | Out-Null }
if (-not [bool]$status.repo_root_detected) { $blockers.Add("repo_root_not_detected") | Out-Null }
if (-not [bool]$status.service_installed) { $warnings.Add("service_not_installed_metadata_missing") | Out-Null }

if ($Command -eq "status" -or $Command -eq "safe-summary") {
  $report = New-LiveHeartbeatReport -Mode "status" -Ok ($blockers.Count -eq 0) -ReviewReason "status_only" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "resolve_live_heartbeat_blockers" } else { "run_worker_live_heartbeat_preview" }) -WouldMutateServer $false -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities
} elseif ($Command -eq "preview") {
  $report = New-LiveHeartbeatReport -Mode "preview" -Ok ($blockers.Count -eq 0) -ReviewReason "preview_only_no_server_mutation" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "resolve_live_heartbeat_blockers" } else { "live_heartbeat_apply_requires_exact_confirmation" }) -WouldMutateServer $false -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities
} else {
  if (-not $Confirm -or $ConfirmationText -ne $HeartbeatConfirmationText) {
    $report = New-LiveHeartbeatReport -Mode "apply" -Ok $false -ReviewReason "missing_exact_confirmation" -RecommendedNextAction "rerun_with_exact_live_heartbeat_confirmation_text" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities
  } elseif ($blockers.Count -gt 0) {
    $report = New-LiveHeartbeatReport -Mode "apply" -Ok $false -ReviewReason "blocked_before_server_mutation" -RecommendedNextAction "resolve_live_heartbeat_blockers" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities
  } else {
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $register = Invoke-WorkerApi -Method "POST" -Path "/v1/workers/register" -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile -Body ([ordered]@{
      worker_id = $resolvedWorkerId
      name = $resolvedWorkerName
      provider = $resolvedProvider
      capabilities = @($capabilities)
      labels = @("bootstrap-alpha", "mg331", "heartbeat-only")
      enabled = $true
      auth_mode = "bearer_token"
      api_base = $resolvedApiBase
      allow_remote_server = $true
    })
    if ($register.status_code -lt 200 -or $register.status_code -ge 300) {
      $report = New-LiveHeartbeatReport -Mode "apply" -Ok $false -ReviewReason "worker_register_failed" -RecommendedNextAction "check_api_base_and_worker_token" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @("worker_register_failed") -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities -RegisterResponse $register
    } else {
      $heartbeat = Invoke-WorkerApi -Method "POST" -Path ("/v1/workers/{0}/heartbeat" -f [uri]::EscapeDataString($resolvedWorkerId)) -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile -Body ([ordered]@{
        status_note = "mg331_live_heartbeat_only_no_task_claim_no_execution"
        load = 0
        seen_at = $now
      })
      if ($heartbeat.status_code -lt 200 -or $heartbeat.status_code -ge 300) {
        $report = New-LiveHeartbeatReport -Mode "apply" -Ok $false -ReviewReason "worker_heartbeat_failed" -RecommendedNextAction "check_worker_registration_and_token" -WouldMutateServer $true -ServerMutationPerformed $true -Blockers @("worker_heartbeat_failed") -Warnings @($warnings) -Status $status -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities -RegisterResponse $register -HeartbeatResponse $heartbeat
      } else {
        $worker = Invoke-WorkerApi -Method "GET" -Path ("/v1/workers/{0}" -f [uri]::EscapeDataString($resolvedWorkerId)) -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile
        $workerStatus = "unknown"
        $heartbeatAt = $now
        if ($worker.body -and $worker.body.worker) {
          $workerStatus = [string]$worker.body.worker.status
          if ($worker.body.worker.last_seen_at) { $heartbeatAt = [string]$worker.body.worker.last_seen_at }
        }
        $statePath = Update-WorkerServiceState -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -ResolvedApiBase $resolvedApiBase -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities -CloudStatus $workerStatus -HeartbeatAt $heartbeatAt
        $afterStatus = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
        $report = New-LiveHeartbeatReport -Mode "apply" -Ok $true -ReviewReason "exact_confirmation_received_register_and_heartbeat_only" -RecommendedNextAction "worker_identity_live_heartbeat_online_hold_no_task_execution" -WouldMutateServer $true -ServerMutationPerformed $true -Blockers @() -Warnings @($warnings) -Status $afterStatus -Id $resolvedWorkerId -Name $resolvedWorkerName -ResolvedProvider $resolvedProvider -Capabilities $capabilities -RegisterResponse $register -HeartbeatResponse $heartbeat -WorkerResponse $worker -StatePath $statePath
      }
    }
  }
}

if ($Json) {
  ConvertTo-SkyBridgeJson $report
} else {
  "Worker live heartbeat $($report.mode): ok=$($report.ok)"
  "Worker: $($report.worker_id)"
  "Cloud status: $($report.cloud_worker_status)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
