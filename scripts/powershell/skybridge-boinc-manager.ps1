[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "safe-summary", "action-matrix", "mode-preview", "operator-guidance", "fixture-state")]
  [string]$Command,

  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SkybridgeCoreEngineModules = @("Skybridge.Core.psm1", "Skybridge.WorkunitRegistry.psm1", "Skybridge.QueuePolicy.psm1", "Skybridge.SafetyScanner.psm1")
foreach ($module in $SkybridgeCoreEngineModules) {
  Import-Module (Join-Path $PSScriptRoot "lib/$module") -Force
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true'
}

function New-BoincMode {
  param(
    [string]$ModeId,
    [string]$DisplayName,
    [string]$Description,
    [bool]$Enabled,
    [string]$ReasonDisabled,
    [string[]]$RequiredHumanAction,
    [string[]]$AllowedActions,
    [string[]]$BlockedActions,
    [string]$NextSafeAction
  )
  [pscustomobject]@{
    schema = "skybridge.boinc_mode.v1"
    mode_id = $ModeId
    display_name = $DisplayName
    description = $Description
    enabled = $Enabled
    reason_disabled = if ([string]::IsNullOrWhiteSpace($ReasonDisabled)) { $null } else { $ReasonDisabled }
    required_human_action = @($RequiredHumanAction)
    allowed_actions = @($AllowedActions)
    blocked_actions = @($BlockedActions)
    next_safe_action = $NextSafeAction
    token_printed = $false
  }
}

function Get-WorkunitReadiness {
  $scriptPath = Join-Path $PSScriptRoot "skybridge-workunit-queue.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command readiness -Json
  $raw | ConvertFrom-Json
}

function Get-WorkunitPlan {
  $scriptPath = Join-Path $PSScriptRoot "skybridge-workunit-queue.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command preview -Json
  $raw | ConvertFrom-Json
}

function Get-ManagedModeSummary {
  $scriptPath = Join-Path $PSScriptRoot "skybridge-managed-mode-pilot.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return $null }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command safe-summary -Json
  $raw | ConvertFrom-Json
}

function Get-ManagedModeRunSummary {
  $scriptPath = Join-Path $PSScriptRoot "skybridge-managed-mode-run.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return $null }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command safe-summary -Json
  $raw | ConvertFrom-Json
}

function Get-LocalPolicy {
  $scriptPath = Join-Path $PSScriptRoot "skybridge-local-resource-policy.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Command safe-summary -Json
  ($raw | ConvertFrom-Json).policy
}

function New-Action {
  param([string]$Action, [bool]$Enabled, [string]$ReasonDisabled, [string]$Category)
  [pscustomobject]@{
    action = $Action
    display_name = ($Action -replace "_", " ")
    enabled = $Enabled
    reason_disabled = if ([string]::IsNullOrWhiteSpace($ReasonDisabled)) { $null } else { $ReasonDisabled }
    category = $Category
    token_printed = $false
  }
}

function New-ActionMatrix {
  [pscustomobject]@{
    schema = "skybridge.boinc_operator_action_matrix.v1"
    allowed = @(
      "refresh",
      "open_logs",
      "view_worker",
      "view_workunits",
      "view_task_pr",
      "view_finalizer_report",
      "safe_pause_metadata",
      "safe_stop_metadata"
    ) | ForEach-Object { New-Action $_ $true $null "allowed" }
    disabled = @(
      "start_one_apply",
      "start_queue_apply",
      "bounded_queue_apply",
      "start_all",
      "resume_execution",
      "worker_claim",
      "task_execution",
      "auto_merge"
    ) | ForEach-Object { New-Action $_ $false "execution_disabled_in_goal_205a_preview_only" "disabled" }
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-Modes {
  $readiness = Get-WorkunitReadiness
  @(
    New-BoincMode "standby" "Standby" "Read-only operator view with local resident worker visibility." $true $null @() @("refresh", "open_logs", "view_worker", "view_workunits") @("start_all", "worker_claim", "task_execution") "Refresh status or inspect completed bootstrap trial evidence."
    New-BoincMode "armed_preview" "Armed Preview" "Preview-only planning state; no claims, tasks, runners or execution are created." $true $null @("review_action_matrix") @("refresh", "view_workunits", "view_finalizer_report") @("start_one_apply", "start_queue_apply", "bounded_queue_apply") "Review the action matrix and keep apply paths disabled."
    New-BoincMode "start_one_review" "Start-One Review" "Historical review of the completed one-shot bootstrap task." $false "bootstrap_trial_completed_no_second_task_authorized" @("review_pr_124_and_finalizer_report") @("view_task_pr", "view_finalizer_report") @("create_task_pr", "auto_merge", "task_execution") "Use the finalizer evidence as read-only history."
    New-BoincMode "bounded_queue_preview" "Bounded Queue Preview" "Shows the workunit queue plan while apply remains unavailable." $true $null @("review_bounded_queue_readiness") @("view_workunits", "refresh") @("bounded_queue_apply", "worker_claim", "task_execution") $readiness.next_safe_action
    New-BoincMode "bounded_queue_apply_disabled" "Bounded Queue Apply Disabled" "The apply path is intentionally absent for Goal 205A." $false "bounded_queue_apply_not_yet_enabled" @("future_goal_must_authorize_apply") @("view_workunits") @("start_queue_apply", "bounded_queue_apply", "resume_execution") "Keep using preview-only queue state."
    New-BoincMode "managed_mode_disabled" "Managed Mode Disabled" "BOINC-like managed execution is not yet authorized." $false "managed_execution_requires_future_explicit_goal" @("authorize_future_managed_mode_goal") @("refresh", "view_worker") @("worker_claim", "task_execution", "start_all") "Use the manager as a read-only control plane."
    New-BoincMode "emergency_stop" "Emergency Stop" "Metadata-only stop state for already-supported safe stop surfaces." $false "no_active_execution_to_stop" @("use_existing_queue_control_if_a_future_run_is_active") @("safe_stop_metadata") @("start_all", "resume_execution") "No active task is running; remain in Standby."
    New-BoincMode "completed_bootstrap_trial" "Completed Bootstrap Trial" "Goal 201/202B finalizer evidence shows bootstrap-trial-201 is complete." $true $null @() @("view_task_pr", "view_finalizer_report") @("create_task_pr", "auto_merge", "second_task") "Use the completed trial as the reference workunit history."
  )
}

function New-ReviewHolds {
  $readiness = Get-WorkunitReadiness
  @(
    [pscustomobject]@{
      schema = "skybridge.boinc_review_hold.v1"
      hold_id = "bounded-queue-apply-disabled"
      hold_type = "execution_disabled"
      title = "Bounded queue apply disabled"
      status = "active"
      reason = "Goal 205A exposes manager controls but does not authorize apply."
      next_safe_action = $readiness.next_safe_action
      token_printed = $false
    }
    [pscustomobject]@{
      schema = "skybridge.boinc_review_hold.v1"
      hold_id = "bootstrap-trial-201-completed"
      hold_type = "bootstrap_completed"
      title = "bootstrap-trial-201 completed"
      status = "completed"
      reason = "Goal 202B finalizer recorded bootstrap_trial_completed after PR #124 merged."
      next_safe_action = "Reference the finalizer report; do not create another task."
      token_printed = $false
    }
  )
}

function New-ControlSurface {
  $modes = @(New-Modes)
  [pscustomobject]@{
    schema = "skybridge.boinc_control_surface.v1"
    project_id = "skybridge-agent-hub"
    current_mode = $modes[0]
    modes = $modes
    action_matrix = New-ActionMatrix
    review_holds = @(New-ReviewHolds)
    bounded_queue_readiness = Get-WorkunitReadiness
    workunit_preview_plan = Get-WorkunitPlan
    completed_bootstrap_trial = [pscustomobject]@{
      campaign_id = "bootstrap-trial-201"
      final_state = "bootstrap_trial_completed"
      task_pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124"
      finalizer_report = ".agent/tmp/bootstrap-trial-201-one-shot/finalizer-evidence.json"
      token_printed = $false
    }
    token_printed = $false
  }
}

function New-ManagerState {
  $surface = New-ControlSurface
  [pscustomobject]@{
    schema = "skybridge.boinc_manager_state.v1"
    project_id = "skybridge-agent-hub"
    product_name = "SkyBridge Agent Hub"
    control_surface = $surface
    local_resident_state = [pscustomobject]@{
      schema = "skybridge.desktop_resident_state.v1"
      worker_id = "laptop-zenbookduo"
      resident_mode = "standby"
      tray_available = $true
      window_visible = $true
      token_printed = $false
    }
    local_worker_supervisor_state = [pscustomobject]@{
      schema = "skybridge.local_worker_supervisor_state.v1"
      worker_id = "laptop-zenbookduo"
      worker_service_mode = "standby"
      can_claim_tasks = $false
      can_execute_tasks = $false
      readiness_blockers = @("execution_disabled_in_goal_205a")
      token_printed = $false
    }
    local_resource_policy = Get-LocalPolicy
    workunit_preview_plan = $surface.workunit_preview_plan
    bounded_queue_readiness = $surface.bounded_queue_readiness
    active_holds = @($surface.review_holds | Where-Object { $_.status -eq "active" })
    next_safe_action = $surface.current_mode.next_safe_action
    token_printed = $false
  }
}

function New-SafeSummary {
  $state = New-ManagerState
  $managedMode = Get-ManagedModeSummary
  $managedModeRun = Get-ManagedModeRunSummary
  [pscustomobject]@{
    schema = "skybridge.boinc_manager_safe_summary.v1"
    project_id = $state.project_id
    mode_id = $state.control_surface.current_mode.mode_id
    mode_display_name = $state.control_surface.current_mode.display_name
    managed_mode_v1 = "pilot only"
    managed_mode_v1_summary = if ($managedModeRun -and $managedModeRun.managed_mode_run_209_state -eq "managed_mode_run_209_completed") { "managed_mode_run_209_completed; one-at-a-time mode ready for future explicit goal; general bounded queue apply disabled; no_next_execution_authorized." } elseif ($managedModeRun) { "Managed Mode Pilot 208 completed; next mode repeatable one-at-a-time preview; general bounded queue disabled." } elseif ($managedMode -and $managedMode.managed_mode_pilot_state -eq "managed_mode_pilot_completed") { "Managed Mode Pilot 208 completed; no next execution authorized." } else { "Managed Mode v1: pilot only; general apply disabled; one-workunit pilot possible only after gate" }
    managed_mode_pilot_state = if ($managedMode) { $managedMode.managed_mode_pilot_state } else { "unknown" }
    managed_mode_pilot_208 = if ($managedModeRun) { $managedModeRun.managed_mode_pilot_208 } else { "unknown" }
    next_mode = if ($managedModeRun) { $managedModeRun.next_mode } else { "preview unavailable" }
    next_run_id = if ($managedModeRun) { $managedModeRun.next_run_id } else { $null }
    managed_mode_run_209_state = if ($managedModeRun -and $managedModeRun.managed_mode_run_209_state) { $managedModeRun.managed_mode_run_209_state } else { "unknown" }
    general_apply = "disabled"
    general_bounded_queue_apply_enabled = $false
    general_bounded_queue = "disabled"
    one_at_a_time_run_apply_enabled = $false
    apply_disabled_reason = if ($managedModeRun) { $managedModeRun.apply_disabled_reason } else { "one_at_a_time_run_apply_disabled_by_default" }
    pilot_bounded_queue_apply_enabled = if ($managedMode) { [bool]$managedMode.pilot_bounded_queue_apply_enabled } else { $false }
    one_workunit_pilot_possible_only_after_gate = $true
    enabled = $state.control_surface.current_mode.enabled
    bounded_queue_apply_available = $false
    can_start_bounded_queue = $false
    active_hold_count = @($state.active_holds).Count
    completed_bootstrap_trial = $true
    disabled_execution_actions = @($state.control_surface.action_matrix.disabled | ForEach-Object { $_.action })
    allowed_operator_actions = @($state.control_surface.action_matrix.allowed | ForEach-Object { $_.action })
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    no_next_execution_authorized = if ($managedModeRun -and ($managedModeRun.PSObject.Properties.Name -contains "no_next_execution_authorized")) { [bool]$managedModeRun.no_next_execution_authorized } elseif ($managedMode) { [bool]$managedMode.no_next_execution_authorized } else { $false }
    next_safe_action = if ($managedModeRun) { $managedModeRun.next_safe_action } elseif ($managedMode -and $managedMode.managed_mode_pilot_state -eq "managed_mode_pilot_completed") { "plan next managed-mode repeatability goal" } else { $state.next_safe_action }
    token_printed = $false
  }
}

$result = switch ($Command) {
  "status" { New-ManagerState }
  "safe-summary" { New-SafeSummary }
  "action-matrix" { New-ActionMatrix }
  "mode-preview" { [pscustomobject]@{ schema = "skybridge.boinc_mode_preview.v1"; modes = @(New-Modes); token_printed = $false } }
  "operator-guidance" {
    $summary = New-SafeSummary
    [pscustomobject]@{
      schema = "skybridge.boinc_operator_guidance.v1"
      next_safe_action = "Review BOINC manager state, worker status, and bounded queue preview; do not start execution."
      allowed_operator_actions = $summary.allowed_operator_actions
      disabled_execution_actions = $summary.disabled_execution_actions
      hard_boundary = "no_start_all_no_bounded_queue_apply_no_task_claim_no_execution"
      token_printed = $false
    }
  }
  "fixture-state" {
    [pscustomobject]@{
      schema = "skybridge.boinc_manager_fixture_state.v1"
      state = New-ManagerState
      summary = New-SafeSummary
      token_printed = $false
    }
  }
}

$text = $result | ConvertTo-Json -Depth 80 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw output field detected." }
if ($Json) { $text } else { $result | Format-List }
