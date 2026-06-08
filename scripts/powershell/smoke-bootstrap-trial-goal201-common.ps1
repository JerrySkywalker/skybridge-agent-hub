[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("contract", "import-reviewed-goal", "start-one-preview", "start-one-gates", "single-task-limit", "worker-route", "no-start-all", "no-second-task", "pr-safety", "evidence", "clean-worktree")]
  [string]$Scenario,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "skybridge-bootstrap-trial-goal201.ps1"

function Invoke-Trial {
  param([string]$Command, [string[]]$Extra = @())
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command @Extra -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  $output | ConvertFrom-Json
}

function Assert-FalseFlag {
  param($Object, [string]$Name)
  if ($Object.PSObject.Properties[$Name] -and $Object.$Name -ne $false) {
    throw "Expected $Name=false."
  }
}

function Assert-SafeJson {
  param($Object)
  $jsonText = $Object | ConvertTo-Json -Depth 100 -Compress
  if ($jsonText -notmatch '"token_printed":false') { throw "Expected token_printed=false." }
  if ($jsonText -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true') {
    throw "Secret-looking or raw-log output detected."
  }
}

$result = switch ($Scenario) {
  "contract" {
    $contract = Invoke-Trial -Command contract
    if (-not $contract.ok) { throw "Contract failed: $(@($contract.errors) -join '; ')" }
    if ($contract.campaign_id -ne "bootstrap-trial-201") { throw "Unexpected campaign id." }
    if ($contract.reviewed_goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { throw "Unexpected goal id." }
    if ($contract.task_type -ne "docs/local-smoke") { throw "Unexpected task type." }
    if ($contract.run_budget.max_steps -ne 1 -or $contract.run_budget.max_tasks -ne 1 -or $contract.run_budget.max_prs -ne 1) { throw "Budget must be one-shot." }
    $contract
  }
  "import-reviewed-goal" {
    $import = Invoke-Trial -Command import-reviewed-goal
    if (-not $import.imported_or_staged -or -not $import.execution_review_required) { throw "Reviewed trial import/stage marker missing." }
    if ($import.proposed_goal_id -ne "proposed-goal-201-local-readme-refresh") { throw "Original proposed goal trace missing." }
    $import
  }
  "start-one-preview" {
    $preview = Invoke-Trial -Command start-one-preview
    if ($preview.selected_goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { throw "Preview selected wrong goal." }
    if ($preview.task_type -ne "docs/local-smoke") { throw "Preview selected wrong task type." }
    if ($preview.would_create_tasks -ne 0) { throw "Preview must not create a task while worker claim is disabled." }
    foreach ($flag in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "pr_created")) { Assert-FalseFlag $preview $flag }
    $preview
  }
  "start-one-gates" {
    $gate = Invoke-Trial -Command start-one-gates -Extra @("-Reason", "smoke gate reason")
    foreach ($required in @("worker_claim_disabled", "worker_execution_disabled")) {
      if (@($gate.blockers) -notcontains $required) { throw "Expected blocker $required." }
    }
    if ($gate.operator_reason_recorded -ne $true) { throw "Operator reason was not recorded." }
    $gate
  }
  "single-task-limit" {
    $contract = Invoke-Trial -Command contract
    $second = Invoke-Trial -Command no-second-task
    if ($contract.run_budget.max_tasks -ne 1 -or $second.second_task_allowed -ne $false) { throw "Single-task limit not enforced." }
    $second
  }
  "worker-route" {
    $route = Invoke-Trial -Command worker-route
    if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { throw "Expected exactly one accepted worker." }
    if (-not $route.selected_worker) { throw "Expected selected worker." }
    foreach ($flag in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "queue_execution_enabled")) { Assert-FalseFlag $route $flag }
    $route
  }
  "no-start-all" {
    $noStartAll = Invoke-Trial -Command no-start-all
    if ($noStartAll.start_all_allowed -ne $false) { throw "start-all must be forbidden." }
    $noStartAll
  }
  "no-second-task" {
    $noSecond = Invoke-Trial -Command no-second-task
    if ($noSecond.second_task_allowed -ne $false -or $noSecond.max_tasks -ne 1) { throw "Second task must be forbidden." }
    $noSecond
  }
  "pr-safety" {
    $pr = Invoke-Trial -Command pr-safety
    if ($pr.target_branch -ne "main") { throw "PR target must be main." }
    if ($pr.auto_merge_enabled -ne $false) { throw "Auto-merge must be disabled." }
    if ($pr.github_settings_mutation_allowed -ne $false) { throw "GitHub settings mutation must be forbidden." }
    $pr
  }
  "evidence" {
    $evidence = Invoke-Trial -Command evidence
    if ($evidence.final_state -ne "held_no_execution_worker_claim_disabled") { throw "Unexpected final state." }
    if ($evidence.lease_outcome -ne "no_lease_created") { throw "No lease should be created." }
    foreach ($flag in @("no_start_all", "no_second_task", "no_auto_merge")) {
      if ($evidence.$flag -ne $true) { throw "Expected $flag=true." }
    }
    $evidence
  }
  "clean-worktree" {
    $before = (git status --short | Out-String).Trim()
    $clean = Invoke-Trial -Command clean-worktree
    $after = (git status --short | Out-String).Trim()
    if ($before -ne $after) { throw "Smoke changed worktree." }
    $clean
  }
}

Assert-SafeJson $result

$summary = [pscustomobject]@{
  ok = $true
  scenario = "bootstrap-trial-goal201-$Scenario"
  result = $result
  executed = $false
  task_created = $false
  task_claimed = $false
  task_executed = $false
  worker_loop_started = $false
  pr_created = $false
  auto_merge_enabled = $false
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 100 -Compress } else { $summary | Format-List }
