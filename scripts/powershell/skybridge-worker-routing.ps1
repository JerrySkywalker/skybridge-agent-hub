[CmdletBinding()]
param(
  [ValidateSet("worker-capability-matrix", "worker-readiness", "worker-route-preview", "worker-route-fixture", "worker-routing-policy", "worker-readiness-summary")]
  [string]$Command = "worker-route-preview",
  [ValidateSet("default", "offline-stale", "disabled-busy", "capability-mismatch", "os-tool-mismatch", "project-repo-access", "max-parallel", "repo-lock", "stale-repo-lock", "all-offline")]
  [string]$Scenario = "default",
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$RepoId = "skybridge-agent-hub",
  [string]$TaskType = "local-smoke",
  [string[]]$RequiredTools = @("git", "node", "pnpm", "powershell"),
  [string[]]$RequiredCapabilities = @("local-smoke"),
  [ValidateSet("windows", "linux", "macos", "unknown", "")]
  [string]$RequiredOs = "windows",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function New-Policy {
  [pscustomobject]@{
    schema = "skybridge.worker_routing_policy.v1"
    default_mode = "preview"
    max_parallel_per_repo = 1
    reject_offline_workers = $true
    reject_stale_workers = $true
    reject_disabled_workers = $true
    reject_busy_workers = $true
    require_capability_match = $true
    require_project_access = $true
    require_repo_access = $true
    require_os_tool_match = $true
    repo_lock_blocks_preview = $true
    stale_repo_lock_requires_recovery_first = $true
    can_claim_tasks = $false
    can_execute_tasks = $false
    token_printed = $false
  }
}

function New-Capability {
  param(
    [string]$WorkerId,
    [string]$Label,
    [string]$Profile,
    [string]$Os,
    [string[]]$Tools,
    [string[]]$TaskTypes,
    [string[]]$Projects,
    [string[]]$Repos,
    [bool]$Frontend = $false,
    [bool]$Backend = $false,
    [bool]$Docs = $false,
    [bool]$WorkerService = $false
  )
  [pscustomobject]@{
    schema = "skybridge.worker_capability_matrix_entry.v1"
    worker_id = $WorkerId
    worker_label = $Label
    worker_profile = $Profile
    os = $Os
    tools = @($Tools)
    task_type_capabilities = @($TaskTypes)
    project_access = @($Projects)
    repo_access = @($Repos)
    can_run_local_smokes = @($TaskTypes) -contains "local-smoke"
    can_run_frontend = $Frontend
    can_run_backend = $Backend
    can_run_docs = $Docs
    can_run_worker_service = $WorkerService
    can_claim_tasks = $false
    can_execute_tasks = $false
    token_printed = $false
  }
}

function Get-Matrix {
  @(
    New-Capability -WorkerId "laptop-zenbookduo" -Label "Jerry Windows standby" -Profile "laptop-zenbookduo-standby" -Os "windows" -Tools @("codex", "git", "node", "pnpm", "powershell") -TaskTypes @("docs", "local-smoke", "frontend", "backend", "worker-service") -Projects @("skybridge-agent-hub") -Repos @("skybridge-agent-hub") -Frontend:$true -Backend:$true -Docs:$true -WorkerService:$true
    New-Capability -WorkerId "linux-ci-preview" -Label "Linux CI preview" -Profile "linux-ci-preview" -Os "linux" -Tools @("git", "node", "pnpm", "bash", "docker") -TaskTypes @("docs", "local-smoke", "frontend", "backend") -Projects @("skybridge-agent-hub") -Repos @("skybridge-agent-hub") -Frontend:$true -Backend:$true -Docs:$true
    New-Capability -WorkerId "docs-disabled" -Label "Docs disabled fixture" -Profile "docs-disabled" -Os "unknown" -Tools @("git") -TaskTypes @("docs") -Projects @("skybridge-agent-hub") -Repos @("skybridge-agent-hub") -Docs:$true
    New-Capability -WorkerId "foreign-repo-worker" -Label "Foreign repo worker" -Profile "foreign-repo-worker" -Os "windows" -Tools @("git", "node", "pnpm", "powershell") -TaskTypes @("docs", "local-smoke") -Projects @("other-project") -Repos @("other-repo") -Docs:$true
  )
}

function New-Readiness {
  param($Capability, [string]$State, [int]$Age, [string]$CurrentTaskId = $null)
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($State -eq "offline") { $blockers.Add("worker_offline") | Out-Null }
  if ($State -eq "stale") { $blockers.Add("worker_stale") | Out-Null }
  if ($State -eq "disabled") { $blockers.Add("worker_disabled") | Out-Null }
  if ($State -eq "busy" -or -not [string]::IsNullOrWhiteSpace($CurrentTaskId)) { $blockers.Add("worker_busy_current_task") | Out-Null }
  $score = switch ($State) {
    "online" { 90 }
    "busy" { 50 }
    "stale" { 30 }
    default { 0 }
  }
  [pscustomobject]@{
    schema = "skybridge.worker_readiness_entry.v1"
    worker_id = $Capability.worker_id
    worker_label = $Capability.worker_label
    readiness_state = $State
    heartbeat_age_seconds = if ($Age -lt 0) { $null } else { $Age }
    current_task_id = $CurrentTaskId
    service_mode = if ($State -eq "online") { "standby" } else { $State }
    readiness_score = $score
    readiness_blockers = @($blockers)
    readiness_warnings = @($(if ($State -eq "online") { "preview_only_execution_gate_disabled" }))
    recommended_action = if ($State -eq "online") { "Worker can be selected for preview only; execution remains disabled." } else { "Resolve readiness blockers before future execution gates." }
    capability_matrix = $Capability
    token_printed = $false
  }
}

function Get-Readiness {
  $matrix = @(Get-Matrix)
  switch ($Scenario) {
    "offline-stale" {
      return @(
        New-Readiness $matrix[0] "offline" -1
        New-Readiness $matrix[1] "stale" 900
        New-Readiness $matrix[2] "online" 8
      )
    }
    "disabled-busy" {
      return @(
        New-Readiness $matrix[0] "busy" 5 "task-in-progress"
        New-Readiness $matrix[1] "online" 9
        New-Readiness $matrix[2] "disabled" -1
      )
    }
    "all-offline" {
      return @(
        New-Readiness $matrix[0] "offline" -1
        New-Readiness $matrix[1] "stale" 900
        New-Readiness $matrix[2] "disabled" -1
      )
    }
    default {
      return @(
        New-Readiness $matrix[0] "online" 12
        New-Readiness $matrix[1] "stale" 900
        New-Readiness $matrix[2] "disabled" -1
        New-Readiness $matrix[3] "online" 6
      )
    }
  }
}

function New-RepoGuard {
  param([int]$ActiveMutatingWorkers = 0, [string]$LockStatus = "none")
  $blocked = $false
  $blocker = $null
  if ($ActiveMutatingWorkers -ge 1) {
    $blocked = $true
    $blocker = "max_parallel_per_repo_exceeded"
  } elseif ($LockStatus -eq "active") {
    $blocked = $true
    $blocker = "active_repo_lock_blocks_routing_preview"
  } elseif ($LockStatus -eq "stale") {
    $blocked = $true
    $blocker = "stale_repo_lock_requires_recovery_first"
  }
  [pscustomobject]@{
    repo_id = $RepoId
    max_parallel_per_repo = 1
    active_mutating_workers = $ActiveMutatingWorkers
    repo_lock_status = $LockStatus
    blocked = $blocked
    blocker = $blocker
    token_printed = $false
  }
}

function New-TaskPreview {
  $effectiveTools = @($RequiredTools)
  $effectiveCapabilities = @($RequiredCapabilities)
  $effectiveOs = if ([string]::IsNullOrWhiteSpace($RequiredOs)) { $null } else { $RequiredOs }
  if ($Scenario -eq "capability-mismatch") { $effectiveCapabilities = @("rust-build") }
  if ($Scenario -eq "os-tool-mismatch") {
    $effectiveOs = "linux"
    $effectiveTools = @("bash", "docker")
  }
  if ($Scenario -eq "project-repo-access") {
    $script:ProjectId = "restricted-project"
    $script:RepoId = "restricted-repo"
  }
  [pscustomobject]@{
    task_id = "preview-super-197-$Scenario"
    task_type = $TaskType
    project_id = $script:ProjectId
    repo_id = $script:RepoId
    required_os = $effectiveOs
    required_tools = @($effectiveTools)
    required_capabilities = @($effectiveCapabilities)
    token_printed = $false
  }
}

function Invoke-RoutePreview {
  $task = New-TaskPreview
  $workers = @(Get-Readiness)
  $guard = switch ($Scenario) {
    "max-parallel" { New-RepoGuard -ActiveMutatingWorkers 1 }
    "repo-lock" { New-RepoGuard -LockStatus "active" }
    "stale-repo-lock" { New-RepoGuard -LockStatus "stale" }
    default { New-RepoGuard }
  }
  $decisions = foreach ($worker in $workers) {
    $reasons = New-Object System.Collections.Generic.List[string]
    if ($worker.readiness_state -eq "offline") { $reasons.Add("worker_offline") | Out-Null }
    if ($worker.readiness_state -eq "stale") { $reasons.Add("worker_stale") | Out-Null }
    if ($worker.readiness_state -eq "disabled") { $reasons.Add("worker_disabled") | Out-Null }
    if ($worker.readiness_state -eq "busy" -or -not [string]::IsNullOrWhiteSpace([string]$worker.current_task_id)) { $reasons.Add("worker_busy_current_task") | Out-Null }
    if (@($worker.capability_matrix.task_type_capabilities) -notcontains $task.task_type) { $reasons.Add("capability_mismatch_task_type") | Out-Null }
    foreach ($capability in @($task.required_capabilities)) {
      if (@($worker.capability_matrix.task_type_capabilities) -notcontains $capability) { $reasons.Add("capability_mismatch_$capability") | Out-Null }
    }
    if (@($worker.capability_matrix.project_access) -notcontains $task.project_id) { $reasons.Add("project_access_mismatch") | Out-Null }
    if (@($worker.capability_matrix.repo_access) -notcontains $task.repo_id) { $reasons.Add("repo_access_mismatch") | Out-Null }
    if ($task.required_os -and [string]$worker.capability_matrix.os -ne [string]$task.required_os) { $reasons.Add("os_mismatch") | Out-Null }
    foreach ($tool in @($task.required_tools)) {
      if (@($worker.capability_matrix.tools) -notcontains $tool) { $reasons.Add("tool_mismatch_$tool") | Out-Null }
    }
    if ($guard.blocked) { $reasons.Add([string]$guard.blocker) | Out-Null }
    [pscustomobject]@{
      worker_id = $worker.worker_id
      worker_label = $worker.worker_label
      accepted = ($reasons.Count -eq 0)
      readiness_score = [int]$worker.readiness_score
      rejection_reasons = @($reasons | Select-Object -Unique)
      warnings = @($worker.readiness_warnings) + @("preview_only_no_task_claim")
      token_printed = $false
    }
  }
  $selected = @($decisions | Where-Object { $_.accepted } | Sort-Object readiness_score -Descending | Select-Object -First 1)[0]
  [pscustomobject]@{
    schema = "skybridge.worker_route_preview.v1"
    ok = $true
    command = $Command
    mode = "preview"
    task = $task
    selected_worker = if ($selected) { $selected } else { $null }
    rejected_workers = @($decisions | Where-Object { -not $_.accepted })
    decisions = @($decisions)
    policy = New-Policy
    repo_parallelism_guard = $guard
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    queue_execution_enabled = $false
    token_printed = $false
  }
}

function New-ReadinessSummary {
  $readiness = @(Get-Readiness)
  $preview = Invoke-RoutePreview
  [pscustomobject]@{
    schema = "skybridge.worker_routing_readiness_detail.v1"
    ok = $true
    command = $Command
    mode = "read"
    worker_pool_counts = [pscustomobject]@{
      total = $readiness.Count
      online = @($readiness | Where-Object readiness_state -eq "online").Count
      stale = @($readiness | Where-Object readiness_state -eq "stale").Count
      offline = @($readiness | Where-Object readiness_state -eq "offline").Count
      disabled = @($readiness | Where-Object readiness_state -eq "disabled").Count
      busy = @($readiness | Where-Object readiness_state -eq "busy").Count
      preview_candidates = @($preview.decisions | Where-Object accepted).Count
    }
    worker_capability_matrix = @(Get-Matrix)
    worker_readiness = $readiness
    route_preview = $preview
    selected_worker_ready_for_preview_only = ($null -ne $preview.selected_worker)
    execution_enabled = $false
    can_start_one = $false
    can_start_queue = $false
    attention_events = @(
      "no_ready_worker"
      "all_workers_offline"
      "worker_stale"
      "worker_disabled"
      "capability_mismatch"
      "repo_parallelism_blocked"
      "selected_worker_ready_for_preview_only"
    )
    token_printed = $false
  }
}

$result = switch ($Command) {
  "worker-capability-matrix" { [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; schema = "skybridge.worker_capability_matrix.v1"; workers = @(Get-Matrix); token_printed = $false } }
  "worker-readiness" { [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; schema = "skybridge.worker_readiness.v1"; workers = @(Get-Readiness); token_printed = $false } }
  "worker-route-preview" { Invoke-RoutePreview }
  "worker-route-fixture" { New-ReadinessSummary }
  "worker-routing-policy" { [pscustomobject]@{ ok = $true; command = $Command; mode = "read"; policy = New-Policy; token_printed = $false } }
  "worker-readiness-summary" { New-ReadinessSummary }
}

$text = $result | ConvertTo-Json -Depth 80 -Compress
if ($text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log') {
  throw "Secret-looking or raw-log field detected."
}
if ($Json) { $text } else { $result | Format-List }
