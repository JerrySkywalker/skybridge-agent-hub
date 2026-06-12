[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("status", "two-workunit-preview", "queue-preview", "apply-gate", "safe-summary", "readiness", "report", "drain-policy", "action-matrix")]
  [string]$Command,

  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [int]$OpenReviewCount = 0,
  [switch]$SimulateOpenReview,
  [switch]$SimulateResourceGateFail,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
}

function Invoke-SafeJsonScript {
  param([Parameter(Mandatory = $true)][string]$ScriptName, [Parameter(Mandatory = $true)][string[]]$Arguments)
  $scriptPath = Join-Path $PSScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return $null }
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scriptPath @Arguments
  $text = ($raw | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($text)) { return $null }
  if (Test-SecretLookingText $text) { throw "Unsafe output detected from $ScriptName." }
  $text | ConvertFrom-Json
}

function New-PreviewPolicy {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_preview_policy.v1"
    max_workunits_preview = 2
    max_apply_workunits = 0
    apply_enabled = $false
    run_apply_enabled = $false
    multi_workunit_apply_enabled = $false
    require_resource_gate = $true
    require_human_review = $true
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    token_printed = $false
  }
}

function Get-ResourceGate {
  if ($SimulateResourceGateFail) {
    return [pscustomobject]@{
      schema = "skybridge.local_run_allowance.v1"
      run_id = "boinc-like-v1-preview"
      explicit_authorization_required = $true
      resource_gate_required = $true
      can_run_one_at_a_time = $false
      blockers = @("simulated_resource_gate_failure")
      token_printed = $false
    }
  }
  $gate = Invoke-SafeJsonScript "skybridge-local-resource-policy.ps1" @("-Command", "run-allowance", "-RunId", "boinc-like-v1-preview", "-Json")
  if ($null -eq $gate) {
    return [pscustomobject]@{
      schema = "skybridge.local_run_allowance.v1"
      run_id = "boinc-like-v1-preview"
      explicit_authorization_required = $true
      resource_gate_required = $true
      can_run_one_at_a_time = $false
      blockers = @("resource_gate_unavailable")
      token_printed = $false
    }
  }
  $gate
}

function Get-OpenReviewCount {
  if ($SimulateOpenReview) { return 1 }
  [Math]::Max(0, $OpenReviewCount)
}

function New-PreviewWorkunit {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [Parameter(Mandatory = $true)][int]$QueueOrder,
    [string]$WaitsFor = $null
  )
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_preview_workunit.v1"
    workunit_id = $Id
    task_id = $null
    project_id = "skybridge-agent-hub"
    task_type = "docs/local-smoke"
    risk = "low"
    queue_order = $QueueOrder
    target_path = $TargetPath
    allowed_paths = @($TargetPath)
    requires_human_review = $true
    repo_mutating = $true
    serialization_group = "repo:skybridge-agent-hub"
    waits_for_workunit_id = $WaitsFor
    state = "preview_only_not_created"
    task_created = $false
    task_claimed = $false
    codex_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-TwoWorkunitPreview {
  $openReviewCount = Get-OpenReviewCount
  $blockedByOpenReview = $openReviewCount -gt 0
  $workunitA = New-PreviewWorkunit "boinc-v1-preview-workunit-a" "docs/boinc-v1-preview-workunit-a.md" 1
  $workunitB = New-PreviewWorkunit "boinc-v1-preview-workunit-b" "docs/boinc-v1-preview-workunit-b.md" 2 $workunitA.workunit_id
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_two_workunit_preview.v1"
    preview_id = "boinc-like-v1-two-workunit-preview"
    mode = "preview"
    policy = New-PreviewPolicy
    workunits = @($workunitA, $workunitB)
    preview_workunit_count = 2
    max_workunits_preview = 2
    max_apply_workunits = 0
    serializes_repo_mutating_work = $true
    no_parallel_mutation_in_one_repo = $true
    workunit_b_waits_for_a_finalized = $true
    open_review_count = $openReviewCount
    blocked_by_open_review = $blockedByOpenReview
    blocked_reason = if ($blockedByOpenReview) { "blocked_by_open_review" } else { "none" }
    apply_enabled = $false
    task_created = $false
    task_claimed = $false
    codex_executed = $false
    pr_created = $false
    no_mutation = $true
    token_printed = $false
  }
}

function New-ApplyGate {
  $resourceGate = Get-ResourceGate
  $preview = New-TwoWorkunitPreview
  $blockers = New-Object System.Collections.Generic.List[string]
  $blockers.Add("apply_disabled") | Out-Null
  $blockers.Add("multi_workunit_apply_disabled") | Out-Null
  if ($preview.blocked_by_open_review) { $blockers.Add("blocked_by_open_review") | Out-Null }
  if ($resourceGate.can_run_one_at_a_time -ne $true) { $blockers.Add("blocked_by_resource_gate") | Out-Null }
  if ($ActiveTasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($StaleLeases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($RunnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_apply_gate.v1"
    can_apply = $false
    apply_enabled = $false
    run_apply_enabled = $false
    multi_workunit_apply_enabled = $false
    max_apply_workunits = 0
    require_resource_gate = $true
    resource_gate = $resourceGate
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    open_review_count = $preview.open_review_count
    blockers = @($blockers | Select-Object -Unique)
    task_created = $false
    task_claimed = $false
    codex_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-DrainPausePolicy {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_drain_pause_policy.v1"
    drain_after_current = $true
    pause_after_current = $true
    pause_new_claims = $true
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    emergency_stop = "preview_only"
    operator_hold = "preview_only"
    resource_gate_hold = "preview_only"
    review_hold = "preview_only"
    worker_started = $false
    worker_stopped = $false
    task_created = $false
    task_claimed = $false
    queue_apply_enabled = $false
    token_printed = $false
  }
}

function New-Action {
  param([string]$Action, [string]$Kind)
  [pscustomobject]@{
    action = $Action
    kind = $Kind
    enabled = $false
    preview_only = $true
    apply_enabled = $false
    reason_disabled = "boinc_v1_preview_only_no_execution_authorized"
    task_created = $false
    task_claimed = $false
    worker_started = $false
    worker_stopped = $false
    token_printed = $false
  }
}

function New-ActionMatrix {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_action_matrix.v1"
    actions = @(
      New-Action "preview" "read_only_preview"
      New-Action "pause" "pause_preview"
      New-Action "drain" "drain_preview"
      New-Action "resume_preview_only" "resume_preview"
      New-Action "emergency_stop_preview" "emergency_stop_preview"
      New-Action "apply_disabled" "disabled_apply"
    )
    all_actions_preview_only = $true
    apply_enabled = $false
    worker_started = $false
    worker_stopped = $false
    task_created = $false
    task_claimed = $false
    token_printed = $false
  }
}

function New-Readiness {
  $preview = New-TwoWorkunitPreview
  $applyGate = New-ApplyGate
  $drain = New-DrainPausePolicy
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_readiness_report.v1"
    readiness_id = "boinc_like_v1_readiness_preview"
    completed_managed_mode_runs = @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")
    resource_gate_state = $applyGate.resource_gate
    worker_readiness_summary = [pscustomobject]@{
      worker_id = "laptop-zenbookduo"
      can_claim_tasks = $false
      can_execute_tasks = $false
      mode = "preview_only"
      token_printed = $false
    }
    scheduler_preview = [pscustomobject]@{
      selected_workunit_count = 2
      max_parallel_per_repo = 1
      serializes_repo_mutating_work = $true
      no_task_claim = $true
      no_execution = $true
      token_printed = $false
    }
    two_workunit_preview = $preview
    drain_pause_policy = $drain
    apply_disabled = $true
    no_next_execution_authorized = $true
    readiness_gaps_before_v1_apply = @(
      "reliable two-workunit finalizer",
      "desktop resident enforcement",
      "failure budget policy",
      "queue drain implementation",
      "operator approval flow",
      "release/audit docs",
      "long-run evidence retention model",
      "explicit v1 authorization goal"
    )
    next_safe_action = "review two-workunit preview and drain policy; keep apply disabled"
    token_printed = $false
  }
}

function New-Status {
  [pscustomobject]@{
    schema = "skybridge.boinc_v1_status.v1"
    status = "preview_ready_apply_disabled"
    preview = New-TwoWorkunitPreview
    apply_gate = New-ApplyGate
    drain_pause_policy = New-DrainPausePolicy
    action_matrix = New-ActionMatrix
    readiness = New-Readiness
    token_printed = $false
  }
}

$result = switch ($Command) {
  "status" { New-Status }
  "two-workunit-preview" { New-TwoWorkunitPreview }
  "queue-preview" { New-TwoWorkunitPreview }
  "apply-gate" { New-ApplyGate }
  "safe-summary" {
    $readiness = New-Readiness
    [pscustomobject]@{
      schema = "skybridge.boinc_v1_safe_summary.v1"
      readiness_id = $readiness.readiness_id
      preview_workunit_count = $readiness.two_workunit_preview.preview_workunit_count
      apply_enabled = $false
      drain_after_current = $readiness.drain_pause_policy.drain_after_current
      pause_after_current = $readiness.drain_pause_policy.pause_after_current
      no_next_execution_authorized = $true
      token_printed = $false
    }
  }
  "readiness" { New-Readiness }
  "report" { New-Readiness }
  "drain-policy" { New-DrainPausePolicy }
  "action-matrix" { New-ActionMatrix }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw output field detected." }
if ($Json) { $text } else { $result | Format-List }
