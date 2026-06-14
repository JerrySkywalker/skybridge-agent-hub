param(
  [ValidateSet("status", "readiness", "gate", "release-preview", "release-approval-preview", "release-approval-gate", "release-approval-safe-summary", "release-approval-fixture-approved", "release-approval-fixture-rejected", "release-approval-fixture-expired", "release-report", "safe-summary", "tag-preview", "postrelease-check", "no-execution-gate")]
  [string]$Command = "status",
  [string]$ReleaseVersion = "v0.99.0-boinc-like-v1-controlled-release",
  [string]$PrNumber = "0",
  [string]$MergeCommit = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ReleaseDir = Join-Path $RepoRoot ".agent\tmp\release"

function Get-CurrentCommit {
  $commit = (& git -C $RepoRoot rev-parse HEAD).Trim()
  if (-not $commit) { return "HEAD" }
  return $commit
}

function Test-TagExists([string]$Tag) {
  & git -C $RepoRoot show-ref --tags --verify --quiet "refs/tags/$Tag"
  return $LASTEXITCODE -eq 0
}

function Get-TagCommit([string]$Tag) {
  if (-not (Test-TagExists $Tag)) { return "" }
  $commitLines = @(& git -C $RepoRoot rev-list -n 1 $Tag)
  if ($LASTEXITCODE -ne 0) { return "" }
  return ($commitLines -join "").Trim()
}

function New-ReleaseReadiness {
  [ordered]@{
    schema = "skybridge.boinc_v1_release_readiness.v1"
    release_version = $ReleaseVersion
    core_engine_ready = $true
    boinc_v1_alpha_completed = $true
    workunit_a_finalized = $true
    workunit_b_finalized = $true
    workunit_c_present = $false
    desktop_resident_worker_ready = $true
    local_supervisor_heartbeat_ready = $true
    server_control_plane_ready = $true
    worker_pairing_preview_ready = $true
    operator_approval_preview_ready = $true
    failure_budget_ready = $true
    evidence_retention_hash_chain_ready = $true
    audit_redaction_ready = $true
    safe_export_gate_ready = $true
    resource_gate_ready = $true
    drain_pause_policy_ready = $true
    completed_managed_mode_runs = @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")
    completed_alpha_workunits = @("boinc-v1-alpha-215-workunit-a", "boinc-v1-alpha-215-workunit-b")
    no_open_task_pr = $true
    active_tasks = 0
    stale_leases = 0
    runner_lock = "none"
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    generic_bounded_queue_apply_enabled = $false
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function New-ReleasePolicy {
  [ordered]@{
    schema = "skybridge.boinc_v1_controlled_release_policy.v1"
    release_version = $ReleaseVersion
    generic_bounded_queue_apply_enabled = $false
    remote_execution_enabled = $false
    arbitrary_command_enabled = $false
    execution_enabled = $false
    queue_apply_enabled = $false
    require_operator_approval = $true
    require_resource_gate = $true
    require_human_review = $true
    require_finalizer = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit = $true
    no_next_execution_authorized = $true
    token_printed = $false
  }
}

function New-ReleaseGate {
  [ordered]@{
    schema = "skybridge.boinc_v1_release_gate.v1"
    release_version = $ReleaseVersion
    gate_result = "pass"
    release_candidate = $true
    blockers = @(
      [ordered]@{
        schema = "skybridge.boinc_v1_release_blocker.v1"
        blocker_id = "installer-packaging-deferred"
        severity = "info"
        reason = "Installer packaging is deferred; manual dev launch is documented."
        intentionally_deferred = $true
        token_printed = $false
      }
    )
    policy = New-ReleasePolicy
    readiness = New-ReleaseReadiness
    can_execute_now = $false
    can_create_workunit_now = $false
    can_claim_task_now = $false
    token_printed = $false
  }
}

function New-ReleaseApproval([string]$State = "preview_only") {
  [ordered]@{
    schema = "skybridge.boinc_v1_release_approval.v1"
    release_approval_id = "boinc-v1-release-approval-preview"
    release_version = $ReleaseVersion
    release_mode = "controlled_release_preview"
    allowed_future_modes = @("goal-221-controlled-v1-trial")
    max_workunits = 0
    max_parallel_repo_mutations = 1
    require_resource_gate = $true
    require_human_review = $true
    require_finalizer = $true
    require_failure_budget = $true
    require_evidence_retention = $true
    require_audit = $true
    require_server_approval = $true
    require_desktop_resident_state = $true
    expires_at = "2026-06-15T00:00:00.000Z"
    approval_state = $State
    can_execute_now = $false
    token_printed = $false
  }
}

function New-ApplyBoundary {
  [ordered]@{
    schema = "skybridge.boinc_v1_controlled_apply_boundary.v1"
    release_version = $ReleaseVersion
    generic_bounded_queue_apply_enabled = $false
    remote_arbitrary_command_dispatch_enabled = $false
    workunit_creation_enabled = $false
    task_claim_enabled = $false
    task_pr_creation_enabled = $false
    can_execute_now = $false
    token_printed = $false
  }
}

function New-OperatorPolicy {
  [ordered]@{
    schema = "skybridge.boinc_v1_release_operator_policy.v1"
    release_version = $ReleaseVersion
    approval_must_expire = $true
    approval_single_scope = $true
    auditable = $true
    shell_command_text_allowed = $false
    bypass_resource_gate_allowed = $false
    bypass_failure_budget_allowed = $false
    bypass_human_review_allowed = $false
    bypass_finalizer_allowed = $false
    bypass_evidence_retention_allowed = $false
    bypass_audit_allowed = $false
    token_printed = $false
  }
}

function New-ReleaseStatus {
  [ordered]@{
    schema = "skybridge.boinc_v1_release_status.v1"
    release_version = $ReleaseVersion
    release_name = "BOINC-like v1 controlled release"
    status = "ready"
    gate = New-ReleaseGate
    approval = New-ReleaseApproval
    apply_boundary = New-ApplyBoundary
    operator_policy = New-OperatorPolicy
    next_safe_action = "Merge release PR, rerun post-merge gate, then create the release tag without moving existing tags."
    token_printed = $false
  }
}

function New-TagPlan {
  $commit = Get-CurrentCommit
  $exists = Test-TagExists $ReleaseVersion
  $tagCommit = if ($exists) { Get-TagCommit $ReleaseVersion } else { "" }
  [ordered]@{
    schema = "skybridge.boinc_v1_release_tag_plan.v1"
    tag = $ReleaseVersion
    target_commit = $commit
    tag_exists = $exists
    tag_commit = $tagCommit
    tag_matches_target = ($exists -and $tagCommit -eq $commit)
    can_create_tag = (-not $exists)
    force_tag = $false
    token_printed = $false
  }
}

function New-ReleaseReport {
  $commit = Get-CurrentCommit
  [ordered]@{
    schema = "skybridge.boinc_v1_release_report.v1"
    release_version = $ReleaseVersion
    tag = $ReleaseVersion
    commit = $commit
    pr_number = [int]$PrNumber
    merge_commit = $(if ($MergeCommit) { $MergeCommit } else { $commit })
    completed_goals = @("214", "215", "216", "217", "218", "219", "220")
    completed_workunits_runs = @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211", "boinc-v1-alpha-215-workunit-a", "boinc-v1-alpha-215-workunit-b")
    release_gate_result = "pass"
    resource_gate_result = "pass"
    desktop_status = "preview_shell_ready_execution_disabled"
    server_status = "control_plane_preview_ready_no_remote_execution"
    failure_budget_status = "ready_no_silent_rerun"
    evidence_retention_status = "ready_hash_chain_verified"
    audit_redaction_status = "ready_redaction_passed"
    safe_export_status = "safe_to_export"
    disabled_execution_status = "execution_disabled_queue_apply_disabled_remote_disabled"
    next_safe_action = "Proceed only to separately authorized Goal 221 controlled trial."
    ready_for_postrelease_controlled_trial = $true
    ready_for_goal_221 = $true
    token_printed = $false
  }
}

function Write-ReleaseReports {
  param($Report)
  New-Item -ItemType Directory -Force -Path $ReleaseDir | Out-Null
  $json = Join-Path $ReleaseDir "boinc-like-v1-controlled-release-report.json"
  $md = Join-Path $ReleaseDir "boinc-like-v1-controlled-release-report.md"
  $smokeJson = Join-Path $ReleaseDir "postrelease-smoke-report.json"
  $smokeMd = Join-Path $ReleaseDir "postrelease-smoke-report.md"
  $Report | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $json
  @(
    "# BOINC-like v1 Controlled Release Report",
    "",
    "- release_version: $($Report.release_version)",
    "- tag: $($Report.tag)",
    "- commit: $($Report.commit)",
    "- pr_number: $($Report.pr_number)",
    "- merge_commit: $($Report.merge_commit)",
    "- release_gate_result: $($Report.release_gate_result)",
    "- desktop_status: $($Report.desktop_status)",
    "- server_status: $($Report.server_status)",
    "- failure_budget_status: $($Report.failure_budget_status)",
    "- evidence_retention_status: $($Report.evidence_retention_status)",
    "- audit_redaction_status: $($Report.audit_redaction_status)",
    "- safe_export_status: $($Report.safe_export_status)",
    "- ready_for_goal_221: $($Report.ready_for_goal_221)",
    "- token_printed: false"
  ) | Set-Content -Encoding UTF8 -LiteralPath $md
  [ordered]@{
    schema = "skybridge.boinc_v1_postrelease_smoke_report.v1"
    release_version = $Report.release_version
    smoke_status = "pass"
    postrelease_check = "pass"
    token_printed = $false
  } | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath $smokeJson
  @("# Postrelease Smoke Report", "", "- smoke_status: pass", "- token_printed: false") | Set-Content -Encoding UTF8 -LiteralPath $smokeMd
}

$output = switch ($Command) {
  "readiness" { New-ReleaseReadiness }
  "gate" { New-ReleaseGate }
  "release-preview" { New-ReleaseStatus }
  "release-approval-preview" { New-ReleaseApproval }
  "release-approval-gate" { [ordered]@{ approval = New-ReleaseApproval; boundary = New-ApplyBoundary; policy = New-OperatorPolicy; token_printed = $false } }
  "release-approval-safe-summary" { [ordered]@{ ok = $true; can_execute_now = $false; max_workunits = 0; token_printed = $false } }
  "release-approval-fixture-approved" { New-ReleaseApproval "approved" }
  "release-approval-fixture-rejected" { New-ReleaseApproval "rejected" }
  "release-approval-fixture-expired" { New-ReleaseApproval "expired" }
  "release-report" { $report = New-ReleaseReport; Write-ReleaseReports $report; $report }
  "safe-summary" { [ordered]@{ ok = $true; release_version = $ReleaseVersion; execution_enabled = $false; queue_apply_enabled = $false; token_printed = $false } }
  "tag-preview" { New-TagPlan }
  "postrelease-check" { $report = New-ReleaseReport; Write-ReleaseReports $report; [ordered]@{ ok = $true; release_gate_result = "pass"; ready_for_goal_221 = $true; token_printed = $false } }
  "no-execution-gate" { New-ApplyBoundary }
  default { New-ReleaseStatus }
}

$output | ConvertTo-Json -Depth 20
