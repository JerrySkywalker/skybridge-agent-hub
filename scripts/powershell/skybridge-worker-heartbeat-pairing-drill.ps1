param(
  [ValidateSet("status", "preview", "apply", "heartbeat-preview", "heartbeat-apply", "safe-summary")]
  [string]$Command = "heartbeat-preview",
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [string]$WorkerId = "local-windows-worker",
  [string]$ServiceName = "SkyBridgeWorkerService",
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
    if (-not (Test-Path -LiteralPath $HomeRoot -PathType Container)) { New-Item -ItemType Directory -Path $HomeRoot | Out-Null }
    return (Resolve-Path -LiteralPath $HomeRoot).Path
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
    if ($match.Success) {
      return $match.Groups[1].Value.Trim()
    }
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
  return [bool]($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|token_printed`"\s*:\s*true|raw_stdout|raw_stderr|raw_prompt")
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
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -ServiceName $ServiceName -HomeRoot $ResolvedHome -RepoRoot $ResolvedRepo -Json
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Update-WorkerServiceState {
  param(
    [string]$ResolvedHome,
    [string]$ResolvedRepo,
    [string]$ResolvedApiBase,
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
  $state = [pscustomobject]@{
    schema = "skybridge.local_worker_service_state.v1"
    service_name = $ServiceName
    worker_id = $WorkerId
    install_strategy = if ($existing -and $existing.install_strategy) { [string]$existing.install_strategy } else { "user_level_heartbeat_only_wrapper" }
    service_installed = $true
    service_running = $false
    service_start_type = "user_level_heartbeat_only_wrapper"
    admin_required = $false
    wrapper_path = Join-Path $ResolvedHome ".skybridge\worker-heartbeat.ps1"
    repo_root = $ResolvedRepo
    api_base_host = Get-SafeApiBaseHost -Value $ResolvedApiBase
    cloud_worker_registered = $true
    cloud_worker_status = $CloudStatus
    last_heartbeat_at = $HeartbeatAt
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

function New-HeartbeatReport {
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
    $RegisterResponse = $null,
    $HeartbeatResponse = $null,
    $WorkerResponse = $null,
    [string]$StatePath = ""
  )
  $workerStatus = "unknown"
  $lastHeartbeat = $null
  if ($WorkerResponse -and $WorkerResponse.body -and $WorkerResponse.body.worker) {
    $workerStatus = [string]$WorkerResponse.body.worker.status
    $lastHeartbeat = $WorkerResponse.body.worker.last_seen_at
  } elseif ($HeartbeatResponse -and $HeartbeatResponse.body -and $HeartbeatResponse.body.worker) {
    $workerStatus = [string]$HeartbeatResponse.body.worker.status
    $lastHeartbeat = $HeartbeatResponse.body.worker.last_seen_at
  }

  [pscustomobject]@{
    schema = "skybridge.worker_heartbeat_pairing_drill.v1"
    ok = $Ok
    command = $Command
    mode = $Mode
    worker_id = $WorkerId
    service_name = $ServiceName
    api_base_configured = -not [string]::IsNullOrWhiteSpace($resolvedApiBase)
    api_base_host = Get-SafeApiBaseHost -Value $resolvedApiBase
    token_file_present = -not [string]::IsNullOrWhiteSpace($resolvedTokenFile) -and (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf)
    token_value_printed = $false
    register_endpoint = "/v1/workers/register"
    heartbeat_endpoint = "/v1/workers/$WorkerId/heartbeat"
    worker_status = $workerStatus
    last_heartbeat_at = $lastHeartbeat
    cloud_worker_registered = $workerStatus -ne "unknown"
    cloud_worker_online = $workerStatus -eq "online"
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

$workerIdExplicit = $PSBoundParameters.ContainsKey("WorkerId") -and -not [string]::IsNullOrWhiteSpace($WorkerId)
$configuredWorkerId = $null
if ([string]::IsNullOrWhiteSpace($WorkerId) -or $WorkerId -eq "local-windows-worker") {
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_ID)) {
    $configuredWorkerId = $env:SKYBRIDGE_WORKER_ID
    $WorkerId = $configuredWorkerId
  } else {
    $configuredWorkerId = Read-ConfigValue -Path $workerConfig -Keys @("SKYBRIDGE_WORKER_ID")
    if (-not [string]::IsNullOrWhiteSpace($configuredWorkerId)) { $WorkerId = $configuredWorkerId }
  }
}
$workerIdConfiguredForMutation = $workerIdExplicit -or -not [string]::IsNullOrWhiteSpace($configuredWorkerId)

$resolvedTokenFile = $TokenFile
if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) { $resolvedTokenFile = $env:SKYBRIDGE_WORKER_TOKEN_FILE }
if ([string]::IsNullOrWhiteSpace($resolvedTokenFile)) { $resolvedTokenFile = Join-Path $resolvedHome ".skybridge\worker-token.txt" }

$status = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
if ([string]::IsNullOrWhiteSpace($resolvedApiBase)) { $blockers.Add("api_base_not_configured") | Out-Null }
if (-not (Test-Path -LiteralPath $resolvedTokenFile -PathType Leaf)) { $blockers.Add("worker_token_file_missing") | Out-Null }
if (-not [bool]$status.service_installed) { $warnings.Add("service_not_installed_metadata_missing") | Out-Null }
if (-not [bool]$status.repo_root_detected) { $blockers.Add("repo_root_not_detected") | Out-Null }
if (-not $workerIdConfiguredForMutation) { $blockers.Add("worker_id_not_configured") | Out-Null }

if ($Command -eq "status" -or $Command -eq "safe-summary") {
  $report = New-HeartbeatReport -Mode "status" -Ok ($blockers.Count -eq 0) -ReviewReason "status_only" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "resolve_heartbeat_pairing_blockers" } else { "run_heartbeat_pairing_preview" }) -WouldMutateServer $false -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status
} elseif ($Command -eq "preview" -or $Command -eq "heartbeat-preview") {
  $report = New-HeartbeatReport -Mode "preview" -Ok ($blockers.Count -eq 0) -ReviewReason "preview_only_no_server_mutation" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "resolve_heartbeat_pairing_blockers" } else { "heartbeat_apply_requires_exact_confirmation" }) -WouldMutateServer $false -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status
} else {
  if (-not $Confirm -or $ConfirmationText -ne $HeartbeatConfirmationText) {
    $report = New-HeartbeatReport -Mode "apply" -Ok $false -ReviewReason "missing_exact_confirmation" -RecommendedNextAction "rerun_with_exact_heartbeat_confirmation_text" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status
  } elseif ($blockers.Count -gt 0) {
    $report = New-HeartbeatReport -Mode "apply" -Ok $false -ReviewReason "blocked_before_server_mutation" -RecommendedNextAction "resolve_heartbeat_pairing_blockers" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @($blockers) -Warnings @($warnings) -Status $status
  } else {
    $now = (Get-Date).ToUniversalTime().ToString("o")
    $capabilities = @("windows", "powershell", "heartbeat_only", "status", "doctor")
    $register = Invoke-WorkerApi -Method "POST" -Path "/v1/workers/register" -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile -Body ([ordered]@{
      worker_id = $WorkerId
      name = $WorkerId
      provider = "skybridge-local-worker-bootstrap-alpha"
      capabilities = $capabilities
      labels = @("bootstrap-alpha", "mg330", "heartbeat-only")
      enabled = $true
      auth_mode = "bearer_token"
      api_base = $resolvedApiBase
      allow_remote_server = $true
    })
    if ($register.status_code -lt 200 -or $register.status_code -ge 300) {
      $report = New-HeartbeatReport -Mode "apply" -Ok $false -ReviewReason "worker_register_failed" -RecommendedNextAction "check_api_base_and_worker_token" -WouldMutateServer $true -ServerMutationPerformed $false -Blockers @("worker_register_failed") -Warnings @($warnings) -Status $status -RegisterResponse $register
    } else {
      $heartbeat = Invoke-WorkerApi -Method "POST" -Path ("/v1/workers/{0}/heartbeat" -f [uri]::EscapeDataString($WorkerId)) -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile -Body ([ordered]@{
        status_note = "mg330_heartbeat_only_no_task_claim_no_execution"
        load = 0
        seen_at = $now
      })
      if ($heartbeat.status_code -lt 200 -or $heartbeat.status_code -ge 300) {
        $report = New-HeartbeatReport -Mode "apply" -Ok $false -ReviewReason "worker_heartbeat_failed" -RecommendedNextAction "check_worker_registration_and_token" -WouldMutateServer $true -ServerMutationPerformed $true -Blockers @("worker_heartbeat_failed") -Warnings @($warnings) -Status $status -RegisterResponse $register -HeartbeatResponse $heartbeat
      } else {
        $worker = Invoke-WorkerApi -Method "GET" -Path ("/v1/workers/{0}" -f [uri]::EscapeDataString($WorkerId)) -ResolvedApiBase $resolvedApiBase -ResolvedTokenFile $resolvedTokenFile
        $workerStatus = "unknown"
        $heartbeatAt = $now
        if ($worker.body -and $worker.body.worker) {
          $workerStatus = [string]$worker.body.worker.status
          if ($worker.body.worker.last_seen_at) { $heartbeatAt = [string]$worker.body.worker.last_seen_at }
        }
        $statePath = Update-WorkerServiceState -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -ResolvedApiBase $resolvedApiBase -CloudStatus $workerStatus -HeartbeatAt $heartbeatAt
        $afterStatus = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
        $report = New-HeartbeatReport -Mode "apply" -Ok $true -ReviewReason "exact_confirmation_received_register_and_heartbeat_only" -RecommendedNextAction "worker_paired_hold_for_no_task_execution" -WouldMutateServer $true -ServerMutationPerformed $true -Blockers @() -Warnings @($warnings) -Status $afterStatus -RegisterResponse $register -HeartbeatResponse $heartbeat -WorkerResponse $worker -StatePath $statePath
      }
    }
  }
}

if ($Json) {
  ConvertTo-SkyBridgeJson $report
} else {
  "Worker heartbeat pairing $($report.mode): ok=$($report.ok)"
  "Worker status: $($report.worker_status)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
