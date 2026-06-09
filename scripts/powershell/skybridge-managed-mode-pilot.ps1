[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "readiness", "plan-preview", "apply-gate", "pilot-preview", "pilot-apply", "evidence", "safe-summary")]
  [string]$Command,

  [string]$PilotId = "managed-mode-pilot-208",
  [ValidateSet("low-docs", "production", "secrets", "github-settings", "auto-merge", "second-workunit", "second-worker", "bad-path")]
  [string]$Scenario = "low-docs",
  [int]$MaxWorkunits = 1,
  [int]$MaxTasks = 1,
  [int]$MaxClaims = 1,
  [int]$MaxCodexExecutions = 1,
  [int]$MaxPrs = 1,
  [int]$MaxRuntimeMinutes = 30,
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$StateDir = ".agent/tmp/managed-mode-pilot-208",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function ConvertTo-ShortPath {
  param([string]$Path)
  $root = Get-RepoRoot
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $Path.Replace("\", "/")
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true'
}

function Get-RunnerLockState {
  $lockPaths = @(
    ".agent/locks/skybridge-edge-worker.lock.json",
    ".agent/tmp/campaign-runner/bootstrap-trial-201.lock.json",
    ".agent/tmp/campaign-runner/dev-queue-189-200.lock.json",
    ".agent/tmp/campaign-runner/managed-mode-pilot-208.lock.json"
  )
  $present = @($lockPaths | Where-Object { Test-Path -LiteralPath (Resolve-RepoPath $_) -PathType Leaf })
  [pscustomobject]@{
    runner_lock_status = if ($present.Count -eq 0) { "none" } else { "present" }
    present_lock_count = $present.Count
    token_printed = $false
  }
}

function Get-GitState {
  $status = (git status --short | Out-String).Trim()
  [pscustomobject]@{
    branch = (git branch --show-current).Trim()
    clean = [string]::IsNullOrWhiteSpace($status)
    status_short = $status
    token_printed = $false
  }
}

function Get-OpenPilotPrs {
  try {
    $output = gh pr list --state open --search "$PilotId in:title,body" --json number,url,title,headRefName,state --limit 20 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    return @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "*Managed Mode Pilot 208*" -or
      [string]$_.title -like "*Task managed-mode-pilot-208-workunit-001*" -or
      [string]$_.headRefName -like "ai/managed-mode-pilot/*"
    })
  } catch {
    return @()
  }
}

function New-PilotPolicy {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_policy.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    max_workunits = $MaxWorkunits
    max_tasks = $MaxTasks
    max_claims = $MaxClaims
    max_codex_executions = $MaxCodexExecutions
    max_prs = $MaxPrs
    max_runtime_minutes = $MaxRuntimeMinutes
    max_parallel_per_repo = 1
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    require_human_review = $true
    allow_task_types = @("docs", "local-smoke", "docs/local-smoke")
    block_task_types = @("production_deploy", "secret_rotation", "server_root_config", "dns", "openresty_config", "hermes_config", "github_settings", "branch_protection", "arbitrary_shell", "auto_execution", "auto_merge")
    allowed_paths = @("README.md", "docs/**")
    selected_worker_id = $WorkerId
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $true
    token_printed = $false
  }
}

function New-PilotWorkunit {
  param([int]$Index = 1)
  $taskType = "docs/local-smoke"
  $risk = "low"
  $allowedPaths = @("README.md", "docs/**")
  $title = "Managed Mode Pilot 208 local smoke documentation orientation"
  $blockers = @()
  if ($Scenario -eq "production") {
    $taskType = "production_deploy"
    $risk = "high"
    $title = "Production deploy"
    $blockers += "blocked_high_risk_surface"
  }
  if ($Scenario -eq "secrets") {
    $taskType = "secret_rotation"
    $risk = "high"
    $title = "Secret rotation"
    $blockers += "blocked_secret_surface"
  }
  if ($Scenario -eq "github-settings") {
    $taskType = "github_settings"
    $risk = "high"
    $allowedPaths = @(".github/**")
    $title = "GitHub branch protection update"
    $blockers += "blocked_github_settings_surface"
  }
  if ($Scenario -eq "auto-merge") {
    $blockers += "auto_merge_forbidden"
  }
  if ($Scenario -eq "bad-path") {
    $allowedPaths = @("apps/server/src/index.ts")
    $blockers += "path_allowlist_violation"
  }
  [pscustomobject]@{
    schema = "skybridge.workunit.v1"
    workunit_id = "managed-mode-pilot-208-workunit-{0:d3}" -f $Index
    project_id = "skybridge-agent-hub"
    campaign_id = $PilotId
    goal_id = "goal-208b-one-workunit-bounded-queue-pilot"
    title = $title
    task_id = "managed-mode-pilot-208-task-{0:d3}" -f $Index
    task_type = $taskType
    required_capabilities = @("codex", "repo_local_docs")
    allowed_paths = @($allowedPaths)
    risk = $risk
    state = "ready"
    lease_id = $null
    lease_owner = $null
    retry_count = 0
    max_retries = 0
    result_artifact = "$StateDir/pilot-result.json"
    evidence_artifact = "$StateDir/pilot-evidence.json"
    pr_url = $null
    ci_status = "not_started"
    requires_human_review = $true
    blockers = @($blockers)
    token_printed = $false
  }
}

function New-PilotPlan {
  $workunits = @(New-PilotWorkunit 1)
  if ($Scenario -eq "second-workunit") { $workunits += New-PilotWorkunit 2 }
  $routes = @(
    [pscustomobject]@{
      workunit_id = $workunits[0].workunit_id
      selected_worker_id = $WorkerId
      queue_order = 1
      token_printed = $false
    }
  )
  if ($Scenario -eq "second-worker") {
    $routes += [pscustomobject]@{
      workunit_id = $workunits[0].workunit_id
      selected_worker_id = "linux-ci-preview"
      queue_order = 1
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_apply_request.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    plan_id = "managed-mode-pilot-208-plan-preview"
    policy = New-PilotPolicy
    workunits = @($workunits)
    selected_routes = @($routes)
    selected_worker_count = @($routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count
    selected_workunit_count = @($workunits).Count
    would_create_tasks = $true
    would_claim_tasks = $true
    would_execute_tasks = $true
    would_create_prs = $true
    would_start_runner = $false
    no_mutation = $true
    token_printed = $false
  }
}

function New-ApplyGate {
  $policy = New-PilotPolicy
  $plan = New-PilotPlan
  $runner = Get-RunnerLockState
  $openPrs = @(Get-OpenPilotPrs)
  $blockers = New-Object System.Collections.Generic.List[string]

  if ($PilotId -ne "managed-mode-pilot-208") { $blockers.Add("pilot_id_not_explicitly_authorized") | Out-Null }
  if ($policy.max_workunits -ne 1 -or @($plan.workunits).Count -ne 1) { $blockers.Add("max_workunits_must_equal_1") | Out-Null }
  if ($policy.max_tasks -ne 1) { $blockers.Add("max_tasks_must_equal_1") | Out-Null }
  if ($policy.max_claims -ne 1) { $blockers.Add("max_claims_must_equal_1") | Out-Null }
  if ($policy.max_codex_executions -ne 1) { $blockers.Add("max_codex_executions_must_equal_1") | Out-Null }
  if ($policy.max_prs -ne 1) { $blockers.Add("max_prs_must_equal_1") | Out-Null }
  if ($policy.max_runtime_minutes -gt 30) { $blockers.Add("max_runtime_minutes_too_high") | Out-Null }
  if (-not $policy.stop_on_pr_created) { $blockers.Add("stop_on_pr_created_required") | Out-Null }
  if (-not $policy.stop_on_ci_failure) { $blockers.Add("stop_on_ci_failure_required") | Out-Null }
  if (-not $policy.stop_on_warning) { $blockers.Add("stop_on_warning_required") | Out-Null }
  if (-not $policy.require_human_review) { $blockers.Add("human_review_required") | Out-Null }
  if ($policy.general_bounded_queue_apply_enabled) { $blockers.Add("general_bounded_queue_apply_must_remain_disabled") | Out-Null }
  if (-not $policy.pilot_bounded_queue_apply_enabled) { $blockers.Add("pilot_bounded_queue_apply_not_enabled") | Out-Null }
  if ($WorkerId -ne "laptop-zenbookduo") { $blockers.Add("selected_worker_must_be_laptop_zenbookduo") | Out-Null }
  if (@($plan.selected_routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count -ne 1) { $blockers.Add("exactly_one_worker_required") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if ($openPrs.Count -gt 0) { $blockers.Add("existing_open_pilot_pr") | Out-Null }

  foreach ($workunit in @($plan.workunits)) {
    if ($workunit.risk -ne "low") { $blockers.Add("risk_must_be_low") | Out-Null }
    if ($workunit.task_type -notin @("docs", "local-smoke", "docs/local-smoke")) { $blockers.Add("task_type_not_allowed:$($workunit.task_type)") | Out-Null }
    foreach ($path in @($workunit.allowed_paths)) {
      if ($path -ne "README.md" -and $path -ne "docs/**" -and $path -notlike "docs/*") { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
    }
    foreach ($item in @($workunit.blockers)) { $blockers.Add([string]$item) | Out-Null }
  }

  [pscustomobject]@{
    schema = "skybridge.bounded_queue_apply_gate.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    can_run_pilot = ($blockers.Count -eq 0)
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = ($blockers.Count -eq 0)
    active_tasks = 0
    stale_leases = 0
    runner_lock = $runner.runner_lock_status
    open_pilot_pr_count = $openPrs.Count
    selected_workunit_count = @($plan.workunits).Count
    selected_worker_count = @($plan.selected_routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-Readiness {
  $gate = New-ApplyGate
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_readiness.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    managed_mode_v1 = "pilot only"
    can_start_managed_mode = $false
    can_run_pilot = $gate.can_run_pilot
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $gate.pilot_bounded_queue_apply_enabled
    active_tasks = 0
    stale_leases = 0
    runner_lock = $gate.runner_lock
    blockers = @($gate.blockers)
    token_printed = $false
  }
}

function New-PilotState {
  $gate = New-ApplyGate
  $statePath = Resolve-RepoPath (Join-Path $StateDir "pilot-evidence.json")
  $existing = Test-Path -LiteralPath $statePath -PathType Leaf
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    state = if ($existing) { "held_waiting_human_pr_review" } elseif ($gate.can_run_pilot) { "ready_for_one_workunit_pilot" } else { "pilot_gate_blocked" }
    workunits_executed = if ($existing) { 1 } else { 0 }
    task_count = if ($existing) { 1 } else { 0 }
    claim_count = if ($existing) { 1 } else { 0 }
    codex_execution_count = if ($existing) { 1 } else { 0 }
    pr_count = if ($existing) { 1 } else { 0 }
    evidence_path = if ($existing) { ConvertTo-ShortPath $statePath } else { $null }
    token_printed = $false
  }
}

function Invoke-PilotApply {
  $gate = New-ApplyGate
  if (-not $gate.can_run_pilot) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "pilot_apply_blocked"
      final_state = "pilot_gate_blocked"
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @($gate.blockers)
      token_printed = $false
    }
  }
  return [pscustomobject]@{
    ok = $false
    schema = "skybridge.bounded_queue_apply_result.v1"
    pilot_id = $PilotId
    mode = "pilot_apply_not_implemented_in_readiness_gate"
    final_state = "held_before_execution"
    task_created = $false
    task_claimed = $false
    codex_execution_started = $false
    pr_created = $false
    blockers = @("pilot_executor_requires_goal_208b_actual_apply")
    token_printed = $false
  }
}

function New-SchemaSummary {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_schema_summary.v1"
    schemas = @(
      "skybridge.managed_mode_v1_readiness.v1",
      "skybridge.bounded_queue_apply_gate.v1",
      "skybridge.bounded_queue_apply_request.v1",
      "skybridge.bounded_queue_apply_result.v1",
      "skybridge.managed_mode_pilot_policy.v1",
      "skybridge.managed_mode_pilot_state.v1"
    )
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    token_printed = $false
  }
}

function New-SafeSummary {
  $readiness = New-Readiness
  $gate = New-ApplyGate
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_safe_summary.v1"
    pilot_id = $PilotId
    managed_mode_v1 = "pilot only"
    general_apply = "disabled"
    one_workunit_pilot_possible_only_after_gate = $true
    can_start_managed_mode = $false
    can_run_pilot = $readiness.can_run_pilot
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $gate.pilot_bounded_queue_apply_enabled
    max_workunits = $MaxWorkunits
    max_tasks = $MaxTasks
    max_claims = $MaxClaims
    max_codex_executions = $MaxCodexExecutions
    max_prs = $MaxPrs
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

$result = switch ($Command) {
  "schema" { New-SchemaSummary }
  "readiness" { New-Readiness }
  "plan-preview" { New-PilotPlan }
  "apply-gate" { New-ApplyGate }
  "pilot-preview" { [pscustomobject]@{ schema = "skybridge.managed_mode_pilot_preview.v1"; request = New-PilotPlan; gate = New-ApplyGate; state = New-PilotState; no_mutation = $true; token_printed = $false } }
  "pilot-apply" { Invoke-PilotApply }
  "evidence" { New-PilotState }
  "safe-summary" { New-SafeSummary }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
