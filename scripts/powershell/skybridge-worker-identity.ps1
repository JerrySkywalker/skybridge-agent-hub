param(
  [ValidateSet("status", "preview", "apply", "safe-summary")]
  [string]$Command = "preview",
  [string]$WorkerId = "",
  [string]$WorkerName = "Jerry Windows Local Worker",
  [string]$Provider = "local-windows",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$IdentityConfirmationText = "I_UNDERSTAND_CONFIGURE_LOCAL_WORKER_IDENTITY_NO_TASK_EXECUTION"

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

function ConvertTo-SafeSingleQuotedValue {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return [bool]($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|token|secret|password|cookie|raw_stdout|raw_stderr|raw_prompt|token_printed`"\s*:\s*true")
}

function Test-SafeWorkerId {
  param([string]$Value)
  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match "^[A-Za-z0-9_.-]{3,80}$"
}

function Test-SafeConfigText {
  param([string]$Value, [int]$MaxLength = 120)
  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value.Length -le $MaxLength -and -not (Test-UnsafeText $Value) -and $Value -match "^[\p{L}\p{N} ._:@/\-]+$"
}

function Read-ConfigValue {
  param([string]$Path, [string]$Key)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($text, ("(?m)^\s*(?:\`$env:)?{0}\s*=\s*['""]?([^'""]+)" -f [regex]::Escape($Key)))
  if (-not $match.Success) { return $null }
  return $match.Groups[1].Value.Trim()
}

function Write-ConfigLine {
  param([string]$Path, [string]$Key, [string]$Value)
  $line = ("`$env:{0} = {1}" -f $Key, (ConvertTo-SafeSingleQuotedValue $Value))
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Set-Content -LiteralPath $Path -Value @($line) -Encoding UTF8
    return
  }
  $text = Get-Content -Raw -LiteralPath $Path
  $text = [regex]::Replace($text, "([^\r\n])(\`$env:)", {
    param($Match)
    $Match.Groups[1].Value + "`r`n" + $Match.Groups[2].Value
  })
  if ($text -match ("(?m)^\s*(?:\`$env:)?{0}\s*=" -f [regex]::Escape($Key))) {
    $updated = [regex]::Replace($text, ("(?m)^\s*(?:\`$env:)?{0}\s*=.*$" -f [regex]::Escape($Key)), $line)
    Set-Content -LiteralPath $Path -Value $updated -Encoding UTF8
  } else {
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) {
      Set-Content -LiteralPath $Path -Value ($text + "`r`n") -Encoding UTF8
    } elseif ($text -ne (Get-Content -Raw -LiteralPath $Path)) {
      Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
    }
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
  }
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

function Read-WorkerIdentity {
  param([string]$WorkerConfig)
  $id = $WorkerId
  if ([string]::IsNullOrWhiteSpace($id)) { $id = $env:SKYBRIDGE_WORKER_ID }
  if ([string]::IsNullOrWhiteSpace($id)) { $id = Read-ConfigValue -Path $WorkerConfig -Key "SKYBRIDGE_WORKER_ID" }
  $name = $WorkerName
  if ([string]::IsNullOrWhiteSpace($name)) { $name = $env:SKYBRIDGE_WORKER_NAME }
  if ([string]::IsNullOrWhiteSpace($name)) { $name = Read-ConfigValue -Path $WorkerConfig -Key "SKYBRIDGE_WORKER_NAME" }
  $provider = $Provider
  if ([string]::IsNullOrWhiteSpace($provider)) { $provider = $env:SKYBRIDGE_WORKER_PROVIDER }
  if ([string]::IsNullOrWhiteSpace($provider)) { $provider = Read-ConfigValue -Path $WorkerConfig -Key "SKYBRIDGE_WORKER_PROVIDER" }
  [pscustomobject]@{
    worker_id = $id
    worker_name = $name
    provider = $provider
  }
}

function Write-IdentityState {
  param(
    [string]$StatePath,
    [string]$ResolvedRepo,
    [string]$Id,
    [string]$Name,
    [string]$ResolvedProvider,
    [string[]]$Capabilities
  )
  $existing = $null
  if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try { $existing = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json } catch { $existing = $null }
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
    repo_root = $ResolvedRepo
    cloud_worker_registered = if ($existing) { [bool]$existing.cloud_worker_registered } else { $false }
    cloud_worker_status = if ($existing -and $existing.cloud_worker_status) { [string]$existing.cloud_worker_status } else { "unknown" }
    last_heartbeat_at = if ($existing -and $existing.last_heartbeat_at) { [string]$existing.last_heartbeat_at } else { $null }
    last_live_heartbeat_result = if ($existing -and $existing.last_live_heartbeat_result) { [string]$existing.last_live_heartbeat_result } else { "none" }
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
  $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function New-IdentityReport {
  param(
    [string]$Mode,
    [bool]$Ok,
    [string]$ReviewReason,
    [string]$RecommendedNextAction,
    [bool]$WouldMutate,
    [bool]$DidMutate,
    [string[]]$Blockers,
    [string[]]$Warnings,
    [string[]]$AppliedActions,
    [string]$ResolvedHome,
    [string]$ResolvedRepo,
    [string]$WorkerConfig,
    [string]$StatePath,
    [string]$Id,
    [string]$Name,
    [string]$ResolvedProvider,
    [string[]]$Capabilities
  )
  [pscustomobject]@{
    schema = "skybridge.worker_identity.v1"
    ok = $Ok
    command = $Command
    mode = $Mode
    worker_id = if ([string]::IsNullOrWhiteSpace($Id)) { $null } else { $Id }
    worker_name = if ([string]::IsNullOrWhiteSpace($Name)) { $null } else { $Name }
    provider = if ([string]::IsNullOrWhiteSpace($ResolvedProvider)) { $null } else { $ResolvedProvider }
    preferred_worker_id = "jerry-win-local-01"
    identity_status = if ($Ok -and -not [string]::IsNullOrWhiteSpace($Id)) { "configured_or_previewable" } else { "blocked" }
    worker_config_path = $WorkerConfig
    service_state_path = $StatePath
    home_root = $ResolvedHome
    repo_root = $ResolvedRepo
    capabilities = @($Capabilities)
    labels = @("bootstrap-alpha", "mg331", "heartbeat-only")
    confirmation_required = $true
    confirmation_text = $IdentityConfirmationText
    review_reason = $ReviewReason
    blockers = @($Blockers)
    warnings = @($Warnings)
    applied_actions = @($AppliedActions)
    would_mutate = $WouldMutate
    did_mutate = $DidMutate
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

$resolvedRepo = Resolve-SkyBridgeRepoRoot
$resolvedHome = Resolve-SkyBridgeHomeRoot
$skybridgeDir = Join-Path $resolvedHome ".skybridge"
$stateDir = Join-Path $skybridgeDir "state"
$workerConfig = Join-Path $skybridgeDir "worker.env.ps1"
$statePath = Join-Path $stateDir "worker-service.json"
$identity = Read-WorkerIdentity -WorkerConfig $workerConfig
$capabilities = Get-DetectedCapabilities
$blockers = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
if (-not (Test-SafeWorkerId $identity.worker_id)) { $blockers.Add("worker_id_not_configured") | Out-Null }
if (-not (Test-SafeConfigText $identity.worker_name -MaxLength 120)) { $blockers.Add("worker_name_invalid_or_missing") | Out-Null }
if (-not (Test-SafeWorkerId $identity.provider)) { $blockers.Add("worker_provider_invalid_or_missing") | Out-Null }
if ($identity.worker_id -and [string]$identity.worker_id -ne "jerry-win-local-01") { $warnings.Add("worker_id_differs_from_mg331_target") | Out-Null }

if ($Command -eq "status" -or $Command -eq "safe-summary") {
  $report = New-IdentityReport -Mode "status" -Ok ($blockers.Count -eq 0) -ReviewReason "status_only" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "run_worker_identity_preview_with_worker_id" } else { "run_worker_live_heartbeat_preview" }) -WouldMutate $false -DidMutate $false -Blockers @($blockers) -Warnings @($warnings) -AppliedActions @() -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -WorkerConfig $workerConfig -StatePath $statePath -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
} elseif ($Command -eq "preview") {
  $report = New-IdentityReport -Mode "preview" -Ok ($blockers.Count -eq 0) -ReviewReason "preview_only_no_mutation" -RecommendedNextAction $(if ($blockers.Count -gt 0) { "supply_worker_id_jerry_win_local_01" } else { "identity_apply_requires_exact_confirmation" }) -WouldMutate $false -DidMutate $false -Blockers @($blockers) -Warnings @($warnings) -AppliedActions @() -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -WorkerConfig $workerConfig -StatePath $statePath -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
} else {
  if (-not $Confirm -or $ConfirmationText -ne $IdentityConfirmationText) {
    $report = New-IdentityReport -Mode "apply" -Ok $false -ReviewReason "missing_exact_confirmation" -RecommendedNextAction "rerun_with_exact_identity_confirmation_text" -WouldMutate $true -DidMutate $false -Blockers @($blockers) -Warnings @($warnings) -AppliedActions @() -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -WorkerConfig $workerConfig -StatePath $statePath -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
  } elseif ($blockers.Count -gt 0) {
    $report = New-IdentityReport -Mode "apply" -Ok $false -ReviewReason "blocked_before_local_identity_write" -RecommendedNextAction "resolve_worker_identity_blockers" -WouldMutate $true -DidMutate $false -Blockers @($blockers) -Warnings @($warnings) -AppliedActions @() -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -WorkerConfig $workerConfig -StatePath $statePath -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
  } else {
    New-Item -ItemType Directory -Path $skybridgeDir -Force | Out-Null
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_WORKER_ID" -Value $identity.worker_id
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_WORKER_NAME" -Value $identity.worker_name
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_WORKER_PROVIDER" -Value $identity.provider
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_WORKER_LABELS" -Value "bootstrap-alpha,mg331,heartbeat-only"
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_WORKER_CAPABILITIES" -Value (@($capabilities) -join ",")
    Write-ConfigLine -Path $workerConfig -Key "SKYBRIDGE_REPO_ROOT" -Value $resolvedRepo
    Write-IdentityState -StatePath $statePath -ResolvedRepo $resolvedRepo -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
    $report = New-IdentityReport -Mode "apply" -Ok $true -ReviewReason "exact_confirmation_received_identity_config_only" -RecommendedNextAction "run_worker_live_heartbeat_preview" -WouldMutate $true -DidMutate $true -Blockers @() -Warnings @($warnings) -AppliedActions @("worker_identity_config_written", "safe_identity_state_metadata_written") -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo -WorkerConfig $workerConfig -StatePath $statePath -Id $identity.worker_id -Name $identity.worker_name -ResolvedProvider $identity.provider -Capabilities $capabilities
  }
}

if ($Json) {
  ConvertTo-SkyBridgeJson $report
} else {
  "Worker identity $($report.mode): ok=$($report.ok)"
  "Worker: $($report.worker_id)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
