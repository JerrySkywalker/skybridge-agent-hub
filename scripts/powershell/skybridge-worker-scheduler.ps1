[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "pool", "readiness", "preview", "route-plan", "safe-summary", "fixture-workers", "fixture-workunits")]
  [string]$Command,

  [ValidateSet("default", "stale", "disabled", "capability-mismatch", "repo-parallelism")]
  [string]$Scenario = "default",

  [switch]$Json
)

$ErrorActionPreference = "Stop"

$SkybridgeCoreEngineModules = @("Skybridge.Core.psm1", "Skybridge.QueuePolicy.psm1", "Skybridge.SafetyScanner.psm1")
foreach ($module in $SkybridgeCoreEngineModules) {
  Import-Module (Join-Path $PSScriptRoot "lib/$module") -Force
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true'
}

function New-WorkerProfile {
  param(
    [string]$WorkerId,
    [string]$DisplayName,
    [string]$HostLabel,
    [string]$Os,
    [string[]]$TaskTypes,
    [string[]]$Tools,
    [string[]]$Projects = @("skybridge-agent-hub"),
    [string[]]$Repos = @("skybridge-agent-hub"),
    [string]$Group = "local-preview",
    [string]$Trust = "local_operator"
  )
  [pscustomobject]@{
    schema = "skybridge.worker_profile.v1"
    worker_id = $WorkerId
    display_name = $DisplayName
    host_label = $HostLabel
    os = $Os
    arch = "x64"
    location_label = $Group
    worker_group = $Group
    supported_task_types = @($TaskTypes)
    supported_projects = @($Projects)
    supported_repos = @($Repos)
    tools_available = @($Tools)
    can_claim_tasks = $false
    can_execute_tasks = $false
    max_concurrent_workunits = 1
    heartbeat_at = "2026-06-09T00:00:00.000Z"
    stale_after_seconds = 300
    resource_policy_summary = "preview only; execution disabled"
    trust_level = $Trust
    token_printed = $false
  }
}

function Get-Workers {
  @(
    New-WorkerProfile -WorkerId "laptop-zenbookduo" -DisplayName "Jerry Windows standby" -HostLabel "laptop-zenbookduo" -Os "windows" -TaskTypes @("docs", "local-smoke", "frontend", "backend", "worker-service") -Tools @("codex", "git", "node", "pnpm", "powershell")
    New-WorkerProfile -WorkerId "linux-ci-preview" -DisplayName "Linux CI preview" -HostLabel "linux-ci-preview" -Os "linux" -TaskTypes @("docs", "local-smoke", "frontend", "backend") -Tools @("git", "node", "pnpm", "bash", "docker") -Group "ci-preview" -Trust "ci_fixture"
    New-WorkerProfile -WorkerId "docs-disabled" -DisplayName "Docs disabled fixture" -HostLabel "docs-disabled" -Os "unknown" -TaskTypes @("docs") -Tools @("git") -Group "disabled-fixture" -Trust "untrusted_fixture"
    New-WorkerProfile -WorkerId "foreign-repo-worker" -DisplayName "Foreign repo worker" -HostLabel "foreign-host" -Os "windows" -TaskTypes @("docs", "local-smoke") -Tools @("git", "node", "pnpm", "powershell") -Projects @("other-project") -Repos @("other-repo") -Group "foreign-preview" -Trust "untrusted_fixture"
  )
}

function New-FixtureWorkunits {
  @(
    [pscustomobject]@{
      schema = "skybridge.workunit.v1"
      workunit_id = "workunit-bootstrap-trial-201-task-001"
      project_id = "skybridge-agent-hub"
      campaign_id = "bootstrap-trial-201"
      goal_id = "goal-201-controlled-start-one-bootstrap-trial"
      task_type = "local-smoke"
      repo_id = "skybridge-agent-hub"
      mutates_repo = $true
      explicitly_read_only = $false
      required_os = "windows"
      required_tools = @("git", "node", "pnpm", "powershell")
      required_capabilities = @("local-smoke")
      token_printed = $false
    }
    [pscustomobject]@{
      schema = "skybridge.workunit.v1"
      workunit_id = "workunit-docs-preview-002"
      project_id = "skybridge-agent-hub"
      campaign_id = "bootstrap-trial-201"
      goal_id = "docs-preview"
      task_type = "docs"
      repo_id = "skybridge-agent-hub"
      mutates_repo = $true
      explicitly_read_only = $false
      required_os = $null
      required_tools = @("git")
      required_capabilities = @("docs")
      token_printed = $false
    }
  )
}

function Get-Availability {
  $workers = @(Get-Workers)
  foreach ($worker in $workers) {
    $state = switch ($worker.worker_id) {
      "linux-ci-preview" { if ($Scenario -eq "stale") { "stale" } else { "stale" } }
      "docs-disabled" { "disabled" }
      default { "ready_preview_only" }
    }
    $busy = $null
    if ($Scenario -eq "disabled" -and $worker.worker_id -eq "laptop-zenbookduo") {
      $state = "busy"
      $busy = "fixture-busy-workunit"
    }
    $blockers = @()
    if ($state -eq "stale") { $blockers += "worker_stale" }
    if ($state -eq "disabled") { $blockers += "worker_disabled" }
    if ($state -eq "busy") { $blockers += "worker_busy_current_workunit" }
    [pscustomobject]@{
      schema = "skybridge.worker_availability.v1"
      worker_id = $worker.worker_id
      state = $state
      heartbeat_age_seconds = if ($state -eq "stale") { 900 } elseif ($state -eq "disabled") { $null } else { 12 }
      busy_workunit_id = $busy
      readiness_blockers = @($blockers)
      score = if ($blockers.Count -eq 0) { 90 } else { 0 }
      token_printed = $false
    }
  }
}

function Test-CapabilityMatch {
  param($Worker, $Availability, $Workunit, [int]$QueueOrder)
  $reasons = New-Object System.Collections.Generic.List[string]
  if ($Availability.state -eq "stale") { $reasons.Add("worker_stale") | Out-Null }
  if ($Availability.state -eq "disabled") { $reasons.Add("worker_disabled") | Out-Null }
  if ($Availability.state -eq "busy") { $reasons.Add("worker_busy_current_workunit") | Out-Null }
  if ($Scenario -eq "capability-mismatch" -and $Worker.worker_id -eq "laptop-zenbookduo") { $reasons.Add("worker_capability_mismatch") | Out-Null }
  if (@($Worker.supported_task_types) -notcontains $Workunit.task_type) { $reasons.Add("task_type_mismatch") | Out-Null }
  if (@($Worker.supported_projects) -notcontains $Workunit.project_id) { $reasons.Add("project_mismatch") | Out-Null }
  if (@($Worker.supported_repos) -notcontains $Workunit.repo_id) { $reasons.Add("repo_mismatch") | Out-Null }
  if ($Workunit.required_os -and $Worker.os -ne $Workunit.required_os) { $reasons.Add("os_mismatch") | Out-Null }
  foreach ($tool in @($Workunit.required_tools)) {
    if (@($Worker.tools_available) -notcontains $tool) { $reasons.Add("tool_mismatch_$tool") | Out-Null }
  }
  if ($Scenario -eq "repo-parallelism" -and $Workunit.mutates_repo -and $QueueOrder -gt 1) { $reasons.Add("repo_parallelism_blocks_concurrent_work") | Out-Null }
  [pscustomobject]@{
    schema = "skybridge.worker_capability_match.v1"
    worker_id = $Worker.worker_id
    workunit_id = $Workunit.workunit_id
    accepted = ($reasons.Count -eq 0)
    score = if ($reasons.Count -eq 0) { [int]$Availability.score } else { 0 }
    rejected_reasons = @($reasons | Select-Object -Unique)
    token_printed = $false
  }
}

function New-RoutePlan {
  $workers = @(Get-Workers)
  $availability = @(Get-Availability)
  $workunits = @(New-FixtureWorkunits)
  $selectedRoutes = @()
  $rejections = @()
  $order = 0
  foreach ($workunit in $workunits) {
    $order += 1
    $matches = foreach ($worker in $workers) {
      $available = @($availability | Where-Object worker_id -eq $worker.worker_id)[0]
      Test-CapabilityMatch $worker $available $workunit $order
    }
    $selected = @($matches | Where-Object accepted | Sort-Object score -Descending | Select-Object -First 1)[0]
    foreach ($match in @($matches | Where-Object { -not $_.accepted })) { $rejections += $match }
    $selectedRoutes += [pscustomobject]@{
      workunit_id = $workunit.workunit_id
      selected_worker_id = if ($selected) { $selected.worker_id } else { $null }
      queue_order = $order
      serialized_by_repo_policy = [bool]($workunit.mutates_repo -and $order -gt 1)
      token_printed = $false
    }
  }
  $policyBlockers = @("scheduling_apply_disabled")
  if ($Scenario -eq "repo-parallelism") {
    $policyBlockers += "repo_parallelism_blocks_concurrent_work"
  }
  [pscustomobject]@{
    schema = "skybridge.workunit_route_plan.v1"
    plan_id = "route-plan-preview-bootstrap-trial-201"
    mode = "preview"
    selected_routes = @($selectedRoutes)
    rejected_workers = @($rejections)
    policy_blockers = @($policyBlockers)
    task_claimed = $false
    lease_created = $false
    task_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-Preview {
  $workers = @(Get-Workers)
  $availability = @(Get-Availability)
  $routePlan = New-RoutePlan
  [pscustomobject]@{
    schema = "skybridge.scheduling_preview.v1"
    preview_id = "multi-worker-scheduling-preview-bootstrap-trial-201"
    worker_pool = [pscustomobject]@{
      schema = "skybridge.worker_pool.v1"
      workers = $workers
      groups = @($workers | ForEach-Object { $_.worker_group } | Select-Object -Unique)
      preview_only = $true
      token_printed = $false
    }
    availability = $availability
    scores = @($availability | ForEach-Object {
      [pscustomobject]@{
        schema = "skybridge.worker_score.v1"
        worker_id = $_.worker_id
        score = $_.score
        factors = if ($_.score -gt 0) { @("task_type", "project_repo", "tools", "heartbeat", "trust_level") } else { @() }
        blockers = @($_.readiness_blockers)
        token_printed = $false
      }
    })
    repo_parallelism_policy = [pscustomobject]@{
      schema = "skybridge.repo_parallelism_policy.v1"
      repo_id = "skybridge-agent-hub"
      max_parallel_per_repo = 1
      mutating_work_serialized = $true
      read_only_parallel_allowed_when_explicit = $true
      uncertain_counts_as_mutating = $true
      token_printed = $false
    }
    route_plan = $routePlan
    apply_available = $false
    task_claimed = $false
    lease_created = $false
    task_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-Readiness {
  $preview = New-Preview
  [pscustomobject]@{
    schema = "skybridge.multi_worker_readiness.v1"
    worker_pool_count = @($preview.worker_pool.workers).Count
    ready_preview_only_count = @($preview.availability | Where-Object state -eq "ready_preview_only").Count
    stale_count = @($preview.availability | Where-Object state -eq "stale").Count
    disabled_count = @($preview.availability | Where-Object state -eq "disabled").Count
    apply_available = $false
    blockers = @("scheduling_apply_disabled", "preview_only_no_claim_no_lease_no_execution")
    attention_events = @("multi_worker_preview_available", "worker_stale", "worker_capability_mismatch", "repo_parallelism_blocks_concurrent_work", "scheduling_apply_disabled")
    token_printed = $false
  }
}

$result = switch ($Command) {
  "schema" {
    [pscustomobject]@{
      schema = "skybridge.worker_scheduler_schema_summary.v1"
      schemas = @("skybridge.worker_profile.v1", "skybridge.worker_pool.v1", "skybridge.worker_availability.v1", "skybridge.worker_capability_match.v1", "skybridge.worker_score.v1", "skybridge.scheduling_preview.v1", "skybridge.repo_parallelism_policy.v1", "skybridge.workunit_route_plan.v1", "skybridge.multi_worker_readiness.v1")
      apply_available = $false
      token_printed = $false
    }
  }
  "pool" { (New-Preview).worker_pool }
  "readiness" { New-Readiness }
  "preview" { New-Preview }
  "route-plan" { New-RoutePlan }
  "safe-summary" {
    $preview = New-Preview
    [pscustomobject]@{
      schema = "skybridge.worker_scheduler_safe_summary.v1"
      route_count = @($preview.route_plan.selected_routes).Count
      worker_count = @($preview.worker_pool.workers).Count
      apply_available = $false
      task_claimed = $false
      lease_created = $false
      task_executed = $false
      pr_created = $false
      token_printed = $false
    }
  }
  "fixture-workers" { [pscustomobject]@{ schema = "skybridge.worker_scheduler_fixture_workers.v1"; workers = @(Get-Workers); token_printed = $false } }
  "fixture-workunits" { [pscustomobject]@{ schema = "skybridge.worker_scheduler_fixture_workunits.v1"; workunits = @(New-FixtureWorkunits); token_printed = $false } }
}

$text = $result | ConvertTo-Json -Depth 80 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw output field detected." }
if ($Json) { $text } else { $result | Format-List }
