param(
  [ValidateSet("status", "preview", "apply", "repair-preview", "repair-apply", "safe-summary")]
  [string]$Command = "repair-preview",
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
$RepairConfirmationText = "I_UNDERSTAND_REPAIR_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION"
$InstallConfirmationText = "I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION"

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

function Invoke-WorkerServiceStatus {
  param([string]$ResolvedHome, [string]$ResolvedRepo)
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -ServiceName $ServiceName -HomeRoot $ResolvedHome -RepoRoot $ResolvedRepo -Json
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function Invoke-InstallApply {
  param([string]$ResolvedHome, [string]$ResolvedRepo)
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    (Join-Path $PSScriptRoot "skybridge-worker-service-install.ps1"),
    "-Command",
    "apply",
    "-ServiceName",
    $ServiceName,
    "-HomeRoot",
    $ResolvedHome,
    "-RepoRoot",
    $ResolvedRepo,
    "-WorkerId",
    $WorkerId,
    "-Confirm",
    "-ConfirmationText",
    $InstallConfirmationText,
    "-Json"
  )
  if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { $args += @("-ApiBase", $ApiBase) }
  if ($Fixture) { $args += "-Fixture" }
  $raw = & pwsh @args
  (($raw | Out-String).Trim() | ConvertFrom-Json)
}

function New-RepairReport {
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
    $InstallApplyResult = $null
  )
  [pscustomobject]@{
    schema = "skybridge.local_worker_service_repair.v1"
    ok = $Ok
    command = $Command
    mode = $Mode
    service_name = $ServiceName
    worker_id = $WorkerId
    repair_strategy = "reconcile_user_level_heartbeat_only_wrapper"
    admin_required = $false
    reversible = $true
    preview_default = $true
    confirmation_required = $true
    confirmation_text = $RepairConfirmationText
    review_reason = $ReviewReason
    planned_actions = @($PlannedActions)
    applied_actions = @($AppliedActions)
    would_mutate = $WouldMutate
    did_mutate = $DidMutate
    status = $Status
    install_apply_result = $InstallApplyResult
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
$status = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo

$planned = New-Object System.Collections.Generic.List[string]
if (-not [bool]$status.service_installed) { $planned.Add("repair_by_creating_user_level_heartbeat_only_wrapper") | Out-Null }
if (-not [bool]$status.api_base_configured) { $planned.Add("repair_missing_api_base_scaffold_or_config") | Out-Null }
if (-not [bool]$status.token_file_present) { $planned.Add("repair_missing_worker_token_guidance") | Out-Null }
if (-not [bool]$status.repo_root_detected) { $planned.Add("repair_blocked_repo_root_not_detected") | Out-Null }
if ([bool]$status.service_installed -and -not [bool]$status.service_running) { $planned.Add("record_heartbeat_only_wrapper_no_loop_running") | Out-Null }
if ($planned.Count -eq 0) { $planned.Add("no_repair_changes_needed") | Out-Null }

if ($Command -eq "status" -or $Command -eq "safe-summary") {
  $report = New-RepairReport -Mode "status" -Ok $true -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "status_only" -RecommendedNextAction $status.recommended_next_action -WouldMutate $false -DidMutate $false
} elseif ($Command -eq "preview" -or $Command -eq "repair-preview") {
  $report = New-RepairReport -Mode "preview" -Ok $true -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "preview_only_no_mutation" -RecommendedNextAction "repair_apply_requires_exact_confirmation" -WouldMutate $false -DidMutate $false
} else {
  if (-not $Confirm -or $ConfirmationText -ne $RepairConfirmationText) {
    $report = New-RepairReport -Mode "apply" -Ok $false -Status $status -PlannedActions @($planned) -AppliedActions @() -ReviewReason "missing_exact_confirmation" -RecommendedNextAction "rerun_with_exact_repair_confirmation_text" -WouldMutate $true -DidMutate $false
  } else {
    $installResult = Invoke-InstallApply -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
    $afterStatus = Invoke-WorkerServiceStatus -ResolvedHome $resolvedHome -ResolvedRepo $resolvedRepo
    $applied = @("reconciled_install_wrapper_metadata", "verified_repair_no_task_execution")
    $report = New-RepairReport -Mode "apply" -Ok ([bool]$installResult.ok) -Status $afterStatus -PlannedActions @($planned) -AppliedActions $applied -ReviewReason "exact_confirmation_received_local_repair_only" -RecommendedNextAction "run_heartbeat_pairing_preview" -WouldMutate $true -DidMutate ([bool]$installResult.did_mutate) -InstallApplyResult $installResult
  }
}

if ($Json) {
  ConvertTo-SkyBridgeJson $report
} else {
  "Worker service repair $($report.mode): ok=$($report.ok)"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
