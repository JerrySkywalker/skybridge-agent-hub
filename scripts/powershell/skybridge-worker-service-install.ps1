param(
  [ValidateSet("status", "preview", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$ServiceName = "SkyBridgeWorkerService",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [string]$ApiBase = "",
  [string]$WorkerId = "local-windows-worker",
  [switch]$Fixture,
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$InstallConfirmationText = "I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION"

function ConvertTo-SkyBridgeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 32
}

function Resolve-SkyBridgeRepoRoot {
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) {
    return (Resolve-Path -LiteralPath $RepoRoot).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-SkyBridgeHomeRoot {
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) {
    if (-not (Test-Path -LiteralPath $HomeRoot -PathType Container)) {
      New-Item -ItemType Directory -Path $HomeRoot | Out-Null
    }
    return (Resolve-Path -LiteralPath $HomeRoot).Path
  }
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
  if (-not [string]::IsNullOrWhiteSpace($env:HOME)) { return $env:HOME }
  return "."
}

function ConvertTo-SafeSingleQuotedValue {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
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

function Invoke-WorkerServiceStatus {
  param([string]$ResolvedHome, [string]$ResolvedRepo)
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -ServiceName $ServiceName -HomeRoot $ResolvedHome -RepoRoot $ResolvedRepo -Json
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function New-InstallReport {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Status,
    [string[]]$PlannedActions,
    [string[]]$AppliedActions,
    [string]$ReviewReason,
    [string]$RecommendedNextAction,
    [bool]$WouldMutate,
    [bool]$DidMutate,
    [string]$ResolvedHome,
    [string]$ResolvedRepo,
    [string]$StatePath,
    [string]$HeartbeatScriptPath
  )
  [pscustomobject]@{
    schema = "skybridge.local_worker_service_install.v1"
    ok = $Ok
    command = $Command
    mode = $Mode
    service_name = $ServiceName
    worker_id = $WorkerId
    install_strategy = "user_level_heartbeat_only_wrapper"
    admin_required = $false
    reversible = $true
    preview_default = $true
    confirmation_required = $true
    confirmation_text = $InstallConfirmationText
    review_reason = $ReviewReason
    home_root = $ResolvedHome
    repo_root = $ResolvedRepo
    skybridge_config_path = Join-Path $ResolvedHome ".skybridge\skybridge.env.ps1"
    worker_config_path = Join-Path $ResolvedHome ".skybridge\worker.env.ps1"
    worker_token_path = Join-Path $ResolvedHome ".skybridge\worker-token.txt"
    service_state_path = $StatePath
    worker_heartbeat_script_path = $HeartbeatScriptPath
    api_base_configured = [bool]$Status.api_base_configured
    api_base_host = $Status.api_base_host
    token_file_present = [bool]$Status.token_file_present
    repo_root_detected = [bool]$Status.repo_root_detected
    service_installed = [bool]$Status.service_installed
    service_running = [bool]$Status.service_running
    service_command_preview = "pwsh -NoProfile -ExecutionPolicy Bypass -File $HeartbeatScriptPath -Command heartbeat-preview"
    planned_actions = @($PlannedActions)
    applied_actions = @($AppliedActions)
    would_mutate = $WouldMutate
    did_mutate = $DidMutate
    status = $Status
    recommended_next_action = $RecommendedNextAction
    claim_enabled = $false
    execute_enabled = $false
    template_runner_enabled = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    task_claimed = $false
    notification_sent = $false
    token_printed = $false
  }
}

function Write-ConfigLineIfMissing {
  param([string]$Path, [string]$Key, [string]$Value)
  $line = ("`$env:{0} = {1}" -f $Key, (ConvertTo-SafeSingleQuotedValue $Value))
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Set-Content -LiteralPath $Path -Value @($line) -Encoding UTF8
    return $true
  }
  $text = Get-Content -Raw -LiteralPath $Path
  if ($text -match ("(?m)^\s*(?:\`$env:)?{0}\s*=" -f [regex]::Escape($Key))) { return $false }
  Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
  return $true
}

function Read-ConfigValue {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($text, ("(?m)^\s*(?:\`$env:)?{0}\s*=\s*['""]?([^'""]+)" -f [regex]::Escape($Key)))
  if (-not $match.Success) { return $null }
  $value = $match.Groups[1].Value.Trim()
  if ($value -notmatch "^[A-Za-z0-9_.:@-]{1,80}$") { return $null }
  return $value
}

function Write-WorkerHeartbeatWrapper {
  param([string]$Path, [string]$ResolvedRepo, [string]$ResolvedHome)
  $heartbeatScript = Join-Path $ResolvedRepo "scripts\powershell\skybridge-worker-heartbeat-pairing-drill.ps1"
  $content = @(
    "param(",
    "  [ValidateSet('status', 'heartbeat-preview', 'heartbeat-apply')]",
    "  [string]`$Command = 'heartbeat-preview',",
    "  [switch]`$Json",
    ")",
    "`$ErrorActionPreference = 'Stop'",
    "& $(ConvertTo-SafeSingleQuotedValue $heartbeatScript) -Command `$Command -HomeRoot $(ConvertTo-SafeSingleQuotedValue $ResolvedHome) -RepoRoot $(ConvertTo-SafeSingleQuotedValue $ResolvedRepo) -Json:`$Json"
  )
  Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$resolvedRepo = Resolve-SkyBridgeRepoRoot
$resolvedHome = Resolve-SkyBridgeHomeRoot
$skybridgeDir = Join-Path $resolvedHome ".skybridge"
$stateDir = Join-Path $skybridgeDir "state"
$statePath = Join-Path $stateDir "worker-service.json"
$heartbeatScriptPath = Join-Path $skybridgeDir "worker-heartbeat.ps1"
$workerConfigPath = Join-Path $skybridgeDir "worker.env.ps1"
if ([string]::IsNullOrWhiteSpace($WorkerId) -or $WorkerId -eq "local-windows-worker") {
  if (-not [string]::IsNullOrWhiteSpace($env:SKYBRIDGE_WORKER_ID)) {
    $WorkerId = $env:SKYBRIDGE_WORKER_ID
  } else {
    $configuredWorkerId = Read-ConfigValue -Path $workerConfigPath -Key "SKYBRIDGE_WORKER_ID"
    if (-not [string]::IsNullOrWhiteSpace($configuredWorkerId)) { $WorkerId = $configuredWorkerId }
  }
}
$status = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo

$planned = New-Object System.Collections.Generic.List[string]
if (-not [bool]$status.api_base_configured) {
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { $planned.Add("create_skybridge_env_scaffold_without_secret") | Out-Null } else { $planned.Add("write_skybridge_api_base_config") | Out-Null }
}
if (-not [bool]$status.token_file_present) {
  if ($Fixture) { $planned.Add("write_fixture_worker_token_file_local_temp_only") | Out-Null } else { $planned.Add("create_worker_token_file_example_guidance") | Out-Null }
}
if (-not [bool]$status.service_installed) { $planned.Add("create_user_level_heartbeat_only_worker_wrapper") | Out-Null }
if (-not [bool]$status.repo_root_detected) { $planned.Add("block_until_repo_root_is_detected") | Out-Null }
if ($planned.Count -eq 0) { $planned.Add("no_install_changes_needed") | Out-Null }

if ($Command -eq "status" -or $Command -eq "safe-summary") {
  $report = New-InstallReport -Mode "status" -Ok $true -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "status_only" -RecommendedNextAction $status.recommended_next_action -WouldMutate $false -DidMutate $false -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -StatePath $statePath -HeartbeatScriptPath $heartbeatScriptPath
} elseif ($Command -eq "preview") {
  $report = New-InstallReport -Mode "preview" -Ok $true -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "preview_only_no_mutation" -RecommendedNextAction "apply_requires_exact_confirmation" -WouldMutate $false -DidMutate $false -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -StatePath $statePath -HeartbeatScriptPath $heartbeatScriptPath
} else {
  if (-not $Confirm -or $ConfirmationText -ne $InstallConfirmationText) {
    $report = New-InstallReport -Mode "apply" -Ok $false -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "missing_exact_confirmation" -RecommendedNextAction "rerun_with_exact_confirmation_text" -WouldMutate $true -DidMutate $false -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -StatePath $statePath -HeartbeatScriptPath $heartbeatScriptPath
  } else {
    New-Item -ItemType Directory -Path $skybridgeDir -Force | Out-Null
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $applied = New-Object System.Collections.Generic.List[string]
    $skybridgeConfig = Join-Path $skybridgeDir "skybridge.env.ps1"
    $workerConfig = Join-Path $skybridgeDir "worker.env.ps1"
    $tokenFile = Join-Path $skybridgeDir "worker-token.txt"

    if (-not [string]::IsNullOrWhiteSpace($ApiBase)) {
      if (Write-ConfigLineIfMissing -Path $skybridgeConfig -Key "SKYBRIDGE_API_BASE" -Value $ApiBase) { $applied.Add("skybridge_api_base_configured") | Out-Null }
    } elseif (-not (Test-Path -LiteralPath $skybridgeConfig -PathType Leaf)) {
      Set-Content -LiteralPath $skybridgeConfig -Value @(
        "# SkyBridge local API config scaffold.",
        "# Set SKYBRIDGE_API_BASE here before live heartbeat pairing.",
        "# `$env:SKYBRIDGE_API_BASE = 'https://your-skybridge.example'"
      ) -Encoding UTF8
      $applied.Add("skybridge_env_scaffold_created") | Out-Null
    }

    if (Write-ConfigLineIfMissing -Path $workerConfig -Key "SKYBRIDGE_WORKER_ID" -Value $WorkerId) { $applied.Add("worker_id_configured") | Out-Null }
    if (Write-ConfigLineIfMissing -Path $workerConfig -Key "SKYBRIDGE_REPO_ROOT" -Value $resolvedRepo) { $applied.Add("repo_root_configured") | Out-Null }
    if (Write-ConfigLineIfMissing -Path $workerConfig -Key "SKYBRIDGE_WORKER_SERVICE_NAME" -Value $ServiceName) { $applied.Add("service_name_configured") | Out-Null }

    if ($Fixture -and -not (Test-Path -LiteralPath $tokenFile -PathType Leaf)) {
      Set-Content -LiteralPath $tokenFile -Value "fixture-local-auth-value" -NoNewline -Encoding UTF8
      $applied.Add("fixture_worker_token_file_created") | Out-Null
    } elseif (-not (Test-Path -LiteralPath $tokenFile -PathType Leaf)) {
      Set-Content -LiteralPath (Join-Path $skybridgeDir "worker-token.txt.example") -Value "paste-worker-token-here-and-rename-to-worker-token.txt" -NoNewline -Encoding UTF8
      $applied.Add("worker_token_example_created") | Out-Null
    }

    Write-WorkerHeartbeatWrapper -Path $heartbeatScriptPath -ResolvedRepo $resolvedRepo -ResolvedHome $resolvedHome
    $applied.Add("heartbeat_only_wrapper_written") | Out-Null

    $state = [pscustomobject]@{
      schema = "skybridge.local_worker_service_state.v1"
      service_name = $ServiceName
      worker_id = $WorkerId
      install_strategy = "user_level_heartbeat_only_wrapper"
      service_installed = $true
      service_running = $false
      service_start_type = "user_level_heartbeat_only_wrapper"
      admin_required = $false
      wrapper_path = $heartbeatScriptPath
      repo_root = $resolvedRepo
      api_base_host = Get-SafeApiBaseHost -Value $ApiBase
      cloud_worker_registered = $false
      cloud_worker_status = "unknown"
      last_heartbeat_at = $null
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
    $applied.Add("safe_service_state_metadata_written") | Out-Null

    $afterStatus = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
    $report = New-InstallReport -Mode "apply" -Ok $true -Status $afterStatus -PlannedActions @($planned) -AppliedActions @($applied) -ReviewReason "exact_confirmation_received_local_install_only" -RecommendedNextAction "run_heartbeat_pairing_preview" -WouldMutate $true -DidMutate $true -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -StatePath $statePath -HeartbeatScriptPath $heartbeatScriptPath
  }
}

if ($Json) {
  ConvertTo-SkyBridgeJson $report
} else {
  "Worker service install $($report.mode): ok=$($report.ok)"
  "Strategy: $($report.install_strategy)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
