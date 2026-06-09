[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "preview", "readiness", "safe-summary", "fixture-plan")]
  [string]$Command,

  [switch]$Json
)

$ErrorActionPreference = "Stop"

function New-BoundedQueuePolicy {
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_policy.v1"
    max_steps = 1
    max_tasks = 1
    max_prs = 0
    max_runtime_minutes = 30
    max_parallel_per_repo = 1
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    drain_after_current = $true
    pause_after_current = $true
    require_human_review = $true
    allow_task_types = @("docs_refresh", "infrastructure_preview")
    block_task_types = @("production_change", "server_root_change", "secret_mutation", "unbounded_worker_loop")
    token_printed = $false
  }
}

function New-BootstrapTrialWorkunit {
  [pscustomobject]@{
    schema = "skybridge.workunit.v1"
    workunit_id = "workunit-bootstrap-trial-201-task-001"
    project_id = "skybridge-agent-hub"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    task_type = "docs_refresh"
    required_capabilities = @("codex_exec_adapter", "repo_local_docs")
    allowed_paths = @("docs/local-smoke-orientation.md")
    risk = "low"
    state = "completed"
    lease_id = $null
    lease_owner = $null
    lease_expires_at = $null
    retry_count = 0
    max_retries = 0
    deadline = $null
    result_artifact = ".agent/tmp/bootstrap-trial-201-one-shot/trial-report.json"
    evidence_artifact = ".agent/tmp/bootstrap-trial-201-one-shot/finalizer-evidence.json"
    pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124"
    ci_status = "not_applicable"
    token_printed = $false
  }
}

function New-WorkunitLease {
  [pscustomobject]@{
    schema = "skybridge.workunit_lease.v1"
    lease_id = $null
    lease_owner = $null
    lease_expires_at = $null
    token_printed = $false
  }
}

function New-WorkunitResult {
  $workunit = New-BootstrapTrialWorkunit
  [pscustomobject]@{
    schema = "skybridge.workunit_result.v1"
    result_artifact = $workunit.result_artifact
    evidence_artifact = $workunit.evidence_artifact
    pr_url = $workunit.pr_url
    ci_status = $workunit.ci_status
    token_printed = $false
  }
}

function New-WorkunitState {
  $workunit = New-BootstrapTrialWorkunit
  [pscustomobject]@{
    schema = "skybridge.workunit_state.v1"
    workunit_id = $workunit.workunit_id
    state = $workunit.state
    terminal = $true
    requires_human_review = $false
    token_printed = $false
  }
}

function New-BoundedQueuePlan {
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_plan.v1"
    plan_id = "bounded-queue-preview-bootstrap-trial-201"
    mode = "preview"
    campaign_id = "bootstrap-trial-201"
    project_id = "skybridge-agent-hub"
    policy = New-BoundedQueuePolicy
    workunits = @(New-BootstrapTrialWorkunit)
    would_create_tasks = $false
    would_claim_tasks = $false
    would_execute_tasks = $false
    would_create_prs = $false
    would_start_runner = $false
    no_mutation = $true
    token_printed = $false
  }
}

function New-BoundedQueueReadiness {
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_readiness.v1"
    campaign_id = "bootstrap-trial-201"
    project_id = "skybridge-agent-hub"
    can_start_bounded_queue = $false
    start_bounded_queue_apply_available = $false
    bounded_queue_execution_enabled = $false
    blockers = @("bounded_queue_apply_not_yet_enabled", "requires_future_goal_authorization")
    warnings = @("preview_only_no_task_creation_no_claim_no_execution_no_pr")
    next_safe_action = "Review the workunit preview and keep bounded queue apply disabled until a future explicit goal authorizes execution."
    token_printed = $false
  }
}

function New-SchemaSummary {
  [pscustomobject]@{
    schema = "skybridge.workunit_queue_schema_summary.v1"
    schemas = @(
      "skybridge.workunit.v1",
      "skybridge.workunit_state.v1",
      "skybridge.workunit_lease.v1",
      "skybridge.workunit_result.v1",
      "skybridge.bounded_queue_plan.v1",
      "skybridge.bounded_queue_readiness.v1",
      "skybridge.bounded_queue_policy.v1"
    )
    workunit_states = @("proposed", "ready", "claimed", "running", "succeeded", "failed", "expired", "cancelled", "held_for_review", "completed")
    apply_available = $false
    token_printed = $false
  }
}

function New-SafeSummary {
  $plan = New-BoundedQueuePlan
  $readiness = New-BoundedQueueReadiness
  [pscustomobject]@{
    schema = "skybridge.workunit_queue_safe_summary.v1"
    mode = "preview"
    workunit_count = @($plan.workunits).Count
    bootstrap_trial_workunit_state = $plan.workunits[0].state
    can_start_bounded_queue = $readiness.can_start_bounded_queue
    start_bounded_queue_apply_available = $readiness.start_bounded_queue_apply_available
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    worker_loop_started = $false
    no_start_all = $true
    no_mutation = $true
    blockers = $readiness.blockers
    token_printed = $false
  }
}

switch ($Command) {
  "schema" {
    $result = New-SchemaSummary
  }
  "preview" {
    $result = New-BoundedQueuePlan
  }
  "readiness" {
    $result = New-BoundedQueueReadiness
  }
  "safe-summary" {
    $result = New-SafeSummary
  }
  "fixture-plan" {
    $result = [pscustomobject]@{
      schema = "skybridge.workunit_queue_fixture_plan.v1"
      lease = New-WorkunitLease
      state = New-WorkunitState
      result = New-WorkunitResult
      plan = New-BoundedQueuePlan
      readiness = New-BoundedQueueReadiness
      token_printed = $false
    }
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 20 -Compress
} else {
  $result | Format-List
}
