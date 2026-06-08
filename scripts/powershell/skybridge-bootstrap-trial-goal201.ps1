[CmdletBinding()]
param(
  [ValidateSet("contract", "import-reviewed-goal", "start-one-preview", "start-one-gates", "start-one-apply", "one-shot-claim-gate", "one-shot-executor-gate", "worker-route", "no-start-all", "no-second-task", "pr-safety", "evidence", "clean-worktree")]
  [string]$Command = "contract",
  [string]$CampaignDir = "goals/bootstrap-trial-201",
  [string]$CampaignId = "bootstrap-trial-201",
  [string]$GoalId = "goal-201-controlled-start-one-bootstrap-trial",
  [string]$TaskType = "docs/local-smoke",
  [int]$MaxTasks = 1,
  [int]$MaxPrs = 1,
  [int]$MaxRuntimeMinutes = 30,
  [string[]]$AllowedPaths = @("README.md", "docs/**"),
  [string]$StateDir = ".agent/tmp/bootstrap-trial-201-one-shot",
  [string]$ProposedPath = "goals/proposed/proposed-goal-201-local-readme-refresh.md",
  [string]$Reason,
  [switch]$Apply,
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

function Read-Json {
  param([string]$Path)
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-MetadataFromMarkdown {
  param([string]$Path)
  $raw = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($raw, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { throw "Markdown metadata missing: $(ConvertTo-ShortPath $Path)" }
  $match.Groups[1].Value | ConvertFrom-Json
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript'
}

function Get-GitState {
  $status = (git status --short | Out-String).Trim()
  $branch = (git branch --show-current).Trim()
  $tagExists = -not [string]::IsNullOrWhiteSpace((git tag --list v0.70.0-dev-queue-200-complete | Out-String).Trim())
  [pscustomobject]@{
    branch = $branch
    clean = [string]::IsNullOrWhiteSpace($status)
    status_short = $status
    dev_queue_200_completion_tag_present = $tagExists
    token_printed = $false
  }
}

function Get-RunnerLockState {
  $lockPaths = @(
    ".agent/locks/skybridge-edge-worker.lock.json",
    ".agent/tmp/campaign-runner/bootstrap-trial-201.lock.json",
    ".agent/tmp/campaign-runner/dev-queue-189-200.lock.json"
  )
  $present = @($lockPaths | Where-Object { Test-Path -LiteralPath (Resolve-RepoPath $_) -PathType Leaf })
  [pscustomobject]@{
    runner_lock_status = if ($present.Count -eq 0) { "none" } else { "present" }
    present_lock_count = $present.Count
    token_printed = $false
  }
}

function Get-OneShotStateDir {
  Resolve-RepoPath $StateDir
}

function Get-OneShotClaimEvidencePath {
  Join-Path (Get-OneShotStateDir) "claim-evidence.json"
}

function Get-OneShotExecutorEvidencePath {
  Join-Path (Get-OneShotStateDir) "executor-evidence.json"
}

function Test-BootstrapAllowedPath {
  param([string]$Path)
  $normalized = ([string]$Path).Replace("\", "/")
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function Get-OpenBootstrapTaskPrs {
  try {
    $output = gh pr list --state open --search "bootstrap-trial-201-task-001 in:title,body" --json number,url,title,headRefName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    return @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "Task bootstrap-trial-201-task-001:*" -or
        [string]$_.headRefName -like "ai/edge-worker/bootstrap-trial-201-task-001-*"
    })
  } catch {
    return @()
  }
}

function Get-RoutePreview {
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-routing.ps1") -Command worker-route-preview -TaskType local-smoke -Json | ConvertFrom-Json
}

function Get-WorkerServiceReadiness {
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-service.ps1") -Command readiness -CampaignId bootstrap-trial-201 -CurrentStepId "bootstrap-trial-201:goal-201-controlled-start-one-bootstrap-trial" -CurrentGoalId goal-201-controlled-start-one-bootstrap-trial -Json | ConvertFrom-Json
}

function Get-Contract {
  $campaignPath = Resolve-RepoPath (Join-Path $CampaignDir "campaign.skybridge.json")
  $goalPath = Resolve-RepoPath (Join-Path $CampaignDir "goal-201-controlled-start-one-bootstrap-trial.md")
  $proposedFullPath = Resolve-RepoPath $ProposedPath
  $campaign = Read-Json $campaignPath
  $goalMeta = Get-MetadataFromMarkdown $goalPath
  $proposedMeta = Get-MetadataFromMarkdown $proposedFullPath
  $errors = New-Object System.Collections.Generic.List[string]

  if ($campaign.campaign_id -ne "bootstrap-trial-201") { $errors.Add("unexpected_campaign_id") | Out-Null }
  if (@($campaign.goals).Count -ne 1) { $errors.Add("trial_campaign_must_have_exactly_one_step") | Out-Null }
  if ($campaign.goals[0].goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { $errors.Add("unexpected_goal_id") | Out-Null }
  if ($campaign.goals[0].task_type -ne "docs/local-smoke") { $errors.Add("unexpected_task_type") | Out-Null }
  foreach ($type in @("docs", "local-smoke")) {
    if (@($campaign.safety_policy.allowed_task_types) -notcontains $type) { $errors.Add("missing_allowed_task_type:$type") | Out-Null }
  }
  foreach ($field in @("no_start_all", "no_unbounded_worker_loop", "no_auto_merge")) {
    if ($campaign.safety_policy.$field -ne $true) { $errors.Add("missing_policy:$field") | Out-Null }
  }
  if ([int]$campaign.safety_policy.max_steps -ne 1) { $errors.Add("max_steps_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_tasks -ne 1) { $errors.Add("max_tasks_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_prs -ne 1) { $errors.Add("max_prs_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_parallel_per_repo -ne 1) { $errors.Add("max_parallel_per_repo_not_one") | Out-Null }
  if ($goalMeta.source_proposed_goal_id -ne $proposedMeta.proposed_goal_id) { $errors.Add("source_proposed_goal_mismatch") | Out-Null }
  if ($proposedMeta.safety_classification -ne "low") { $errors.Add("proposed_goal_not_low_risk") | Out-Null }
  foreach ($type in @("docs", "local-smoke")) {
    if (@($proposedMeta.allowed_task_types) -notcontains $type) { $errors.Add("proposed_goal_missing_allowed_type:$type") | Out-Null }
  }

  [pscustomobject]@{
    ok = ($errors.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_contract.v1"
    campaign_id = $campaign.campaign_id
    campaign_path = ConvertTo-ShortPath $campaignPath
    reviewed_goal_path = ConvertTo-ShortPath $goalPath
    proposed_goal_path = ConvertTo-ShortPath $proposedFullPath
    proposed_goal_id = $proposedMeta.proposed_goal_id
    reviewed_goal_id = $goalMeta.goal_id
    title = $goalMeta.title
    payload = $goalMeta.payload
    risk = $goalMeta.risk
    task_type = $goalMeta.task_type
    allowed_task_types = @($campaign.safety_policy.allowed_task_types)
    review_status = $campaign.review_status
    execution_review_required = [bool]$campaign.goals[0].execution_review_required
    run_budget = [pscustomobject]@{
      max_steps = [int]$campaign.safety_policy.max_steps
      max_tasks = [int]$campaign.safety_policy.max_tasks
      max_prs = [int]$campaign.safety_policy.max_prs
      max_runtime_minutes = [int]$campaign.safety_policy.max_runtime_minutes
      max_parallel_per_repo = [int]$campaign.safety_policy.max_parallel_per_repo
      token_printed = $false
    }
    errors = @($errors)
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    token_printed = $false
  }
}

function Get-GateResult {
  $contract = Get-Contract
  $git = Get-GitState
  $runner = Get-RunnerLockState
  $route = Get-RoutePreview
  $service = Get-WorkerServiceReadiness
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]

  if (-not $contract.ok) { foreach ($item in @($contract.errors)) { $blockers.Add([string]$item) | Out-Null } }
  if (-not $git.clean) { $blockers.Add("worktree_dirty") | Out-Null }
  if (-not $git.dev_queue_200_completion_tag_present) { $blockers.Add("dev_queue_200_completion_tag_missing") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (-not $route.selected_worker) { $blockers.Add("no_single_selected_worker") | Out-Null }
  if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { $blockers.Add("route_preview_not_exactly_one_worker") | Out-Null }
  if ($route.policy.max_parallel_per_repo -ne 1) { $blockers.Add("max_parallel_per_repo_not_enforced") | Out-Null }
  if ($route.repo_parallelism_guard.blocked -eq $true) { $blockers.Add("repo_parallelism_blocked") | Out-Null }
  if ($route.task_created -or $route.task_claimed -or $route.task_executed -or $route.worker_loop_started) { $blockers.Add("route_preview_mutated_execution_state") | Out-Null }

  $claimGate = Get-OneShotClaimGate
  $executorGate = Get-OneShotExecutorGate
  if (-not $claimGate.ok) { foreach ($item in @($claimGate.blockers)) { $blockers.Add([string]$item) | Out-Null } }
  if (-not $executorGate.ok) { foreach ($item in @($executorGate.blockers)) { $blockers.Add([string]$item) | Out-Null } }
  $warnings.Add("one_shot_execution_held_until_executor_gate_passes") | Out-Null

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_gate.v1"
    command = $Command
    campaign_id = $contract.campaign_id
    selected_step_id = "$($contract.campaign_id):$($contract.reviewed_goal_id)"
    selected_goal_id = $contract.reviewed_goal_id
    task_type = $contract.task_type
    active_tasks = 0
    stale_leases = 0
    runner_lock_status = $runner.runner_lock_status
    repo_lock_status = "clear"
    route_preview = $route
    selected_worker_id = if ($route.selected_worker) { [string]$route.selected_worker.worker_id } else { $null }
    route_reason = if ($route.selected_worker) { "single accepted local worker selected by docs/local-smoke route preview" } else { "no accepted worker" }
    worker_service_readiness = $service.readiness
    run_budget = $contract.run_budget
    operator_reason_recorded = -not [string]::IsNullOrWhiteSpace($Reason)
    attention_state = "one-shot bootstrap trial held: waiting for executor gate"
    dashboard_state = if ($executorGate.ok) { "ready_for_one_shot_start_one_apply" } else { "held_no_execution_executor_gate_blocked" }
    blockers = @($blockers | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    would_create_tasks = if ($blockers.Count -eq 0) { 1 } else { 0 }
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    start_all_allowed = $false
    second_task_allowed = $false
    external_notification_sent = $false
    token_printed = $false
  }
}

function Get-StartOneApplyResult {
  if ([string]::IsNullOrWhiteSpace($Reason)) { throw "start-one-apply requires -Reason." }
  $gate = Get-GateResult
  if (-not $gate.ok) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
      mode = "held"
      campaign_id = $gate.campaign_id
      attempted = $false
      applied = $false
      task_created = $false
      task_id = $null
      task_claimed = $false
      worker_id = $gate.selected_worker_id
      pr_created = $false
      pr_url = $null
      auto_merge_enabled = $false
      final_state = "held_no_execution_executor_gate_blocked"
      hold_reason = "one-shot worker executor gate cannot be fully enforced"
      blockers = @($gate.blockers)
      gate = $gate
      no_start_all = $true
      no_second_task = $true
      no_unbounded_worker_loop = $true
      no_resume_apply = $true
      token_printed = $false
    }
  }
  [pscustomobject]@{
    ok = $false
    schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
    mode = "held"
    campaign_id = $gate.campaign_id
    attempted = $false
    applied = $false
    task_created = $false
    task_id = $null
    task_claimed = $false
    worker_id = $gate.selected_worker_id
    pr_created = $false
    pr_url = $null
    auto_merge_enabled = $false
    final_state = "ready_for_one_shot_executor"
    hold_reason = "start-one apply dry-run surface only; use one-shot executor after final operator gate"
    blockers = @($gate.blockers)
    gate = $gate
    no_start_all = $true
    no_second_task = $true
    no_unbounded_worker_loop = $true
    no_resume_apply = $true
    token_printed = $false
  }
}

function Get-Evidence {
  $gate = Get-GateResult
  [pscustomobject]@{
    ok = $true
    schema = "skybridge.bootstrap_trial_goal201_evidence.v1"
    campaign_id = $gate.campaign_id
    reviewed_goal_path = (Get-Contract).reviewed_goal_path
    proposed_goal_path = (Get-Contract).proposed_goal_path
    task_id = $null
    pr_url = $null
    selected_worker_id = $gate.selected_worker_id
    route_reason = $gate.route_reason
    run_budget = $gate.run_budget
    lease_outcome = "no_lease_created"
    final_state = "held_no_execution_worker_claim_disabled"
    active_tasks = 0
    stale_leases = 0
    runner_lock_status = $gate.runner_lock_status
    queue_held = $true
    waiting_for_human_pr_review = $false
    no_start_all = $true
    no_second_task = $true
    no_auto_merge = $true
    raw_transcript_included = $false
    raw_logs_included = $false
    external_notification_sent = $false
    token_printed = $false
  }
}

function Get-OneShotClaimGate {
  $contract = Get-Contract
  $git = Get-GitState
  $runner = Get-RunnerLockState
  $route = Get-RoutePreview
  $openPrs = @(Get-OpenBootstrapTaskPrs)
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  $claimEvidencePath = Get-OneShotClaimEvidencePath

  if (-not $contract.ok) { foreach ($item in @($contract.errors)) { $blockers.Add([string]$item) | Out-Null } }
  if ($CampaignId -ne "bootstrap-trial-201") { $blockers.Add("wrong_campaign_refused") | Out-Null }
  if ($GoalId -ne "goal-201-controlled-start-one-bootstrap-trial") { $blockers.Add("wrong_goal_refused") | Out-Null }
  if ($TaskType -ne "docs/local-smoke") { $blockers.Add("wrong_task_type_refused") | Out-Null }
  if ($MaxTasks -ne 1) { $blockers.Add("max_tasks_must_be_1") | Out-Null }
  if ($MaxPrs -ne 1) { $blockers.Add("max_prs_must_be_1") | Out-Null }
  if ($MaxRuntimeMinutes -lt 1 -or $MaxRuntimeMinutes -gt 30) { $blockers.Add("max_runtime_minutes_must_be_bounded_1_to_30") | Out-Null }
  foreach ($path in @($AllowedPaths)) {
    if (-not (Test-BootstrapAllowedPath -Path $path)) { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
  }
  if (-not $git.clean) { $blockers.Add("worktree_dirty") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { $blockers.Add("route_preview_not_exactly_one_worker") | Out-Null }
  if (-not $route.selected_worker -or [string]$route.selected_worker.worker_id -ne "laptop-zenbookduo") { $blockers.Add("selected_worker_not_explicitly_eligible") | Out-Null }
  if ($route.task_created -or $route.task_claimed -or $route.task_executed -or $route.worker_loop_started) { $blockers.Add("route_preview_mutated_execution_state") | Out-Null }
  if ($openPrs.Count -gt 0) { $blockers.Add("existing_open_task_pr_for_bootstrap_trial") | Out-Null }
  if (Test-Path -LiteralPath $claimEvidencePath -PathType Leaf) { $blockers.Add("second_claim_refused") | Out-Null }

  $taskId = "bootstrap-trial-201-task-001"
  $leaseId = "bootstrap-trial-201-lease-001"
  $result = [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_one_shot_claim_gate.v1"
    mode = if ($Apply) { "apply" } else { "preview" }
    mutates = [bool]$Apply
    campaign_id = $CampaignId
    goal_id = $GoalId
    task_type = $TaskType
    task_id = if ($blockers.Count -eq 0) { $taskId } else { $null }
    worker_id = if ($route.selected_worker) { [string]$route.selected_worker.worker_id } else { $null }
    route_reason = if ($route.selected_worker) { "single eligible local worker accepted by route preview" } else { "no eligible worker" }
    run_budget = [pscustomobject]@{
      max_tasks = $MaxTasks
      max_prs = $MaxPrs
      max_runtime_minutes = $MaxRuntimeMinutes
      max_parallel_per_repo = 1
      token_printed = $false
    }
    allowed_paths = @($AllowedPaths)
    active_tasks = 0
    stale_leases = 0
    repo_lock_status = "clear"
    runner_lock_status = $runner.runner_lock_status
    open_task_pr_count = $openPrs.Count
    task_created = $false
    task_claimed = $false
    lease_created = $false
    lease_id = $null
    evidence_path = if ($Apply -and $blockers.Count -eq 0) { ConvertTo-ShortPath $claimEvidencePath } else { $null }
    blockers = @($blockers | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    start_all_allowed = $false
    start_queue_allowed = $false
    second_task_allowed = $false
    token_printed = $false
  }

  if ($Apply -and $result.ok) {
    New-Item -ItemType Directory -Path (Get-OneShotStateDir) -Force | Out-Null
    $result.task_created = $true
    $result.task_claimed = $true
    $result.lease_created = $true
    $result.lease_id = $leaseId
    $safeEvidence = [pscustomobject]@{
      schema = "skybridge.bootstrap_trial_goal201_safe_claim_evidence.v1"
      campaign_id = $CampaignId
      goal_id = $GoalId
      task_id = $taskId
      worker_id = $result.worker_id
      lease_id = $leaseId
      allowed_paths = @($AllowedPaths)
      prompt_included = $false
      raw_transcript_included = $false
      raw_logs_included = $false
      token_printed = $false
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $safeEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $claimEvidencePath -Encoding UTF8
  }
  return $result
}

function Get-OneShotExecutorGate {
  $claimGate = Get-OneShotClaimGate
  $blockers = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($claimGate.blockers)) { $blockers.Add([string]$item) | Out-Null }

  # The current shared Codex executor writes prompt.md, codex-exec.jsonl and local logs.
  # Goal 201B forbids persisting raw prompts/transcripts/logs for the trial evidence path,
  # so actual execution must fail closed until a redacted executor is available.
  $executorScript = Join-Path $PSScriptRoot "invoke-codex-task.ps1"
  $executorText = if (Test-Path -LiteralPath $executorScript -PathType Leaf) { Get-Content -Raw -LiteralPath $executorScript } else { "" }
  if ($executorText -match 'prompt\.md' -or $executorText -match 'codex-exec\.jsonl' -or $executorText -match 'validation-\$index\.log') {
    $blockers.Add("codex_executor_persists_prompt_or_logs") | Out-Null
  }

  foreach ($path in @($AllowedPaths)) {
    if (-not (Test-BootstrapAllowedPath -Path $path)) { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
  }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_one_shot_executor_gate.v1"
    mode = "preview"
    campaign_id = $CampaignId
    goal_id = $GoalId
    task_type = $TaskType
    max_codex_executions = 1
    max_prs = $MaxPrs
    allowed_paths = @($AllowedPaths)
    would_run_codex = ($blockers.Count -eq 0)
    task_claimed = $false
    task_executed = $false
    codex_worker_execution_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    stops_after_pr_or_failure = $true
    prompt_included = $false
    raw_transcript_included = $false
    raw_logs_included = $false
    external_notification_sent = $false
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

$result = switch ($Command) {
  "contract" { Get-Contract }
  "import-reviewed-goal" { $c = Get-Contract; $c | Add-Member -NotePropertyName imported_or_staged -NotePropertyValue $true -Force; $c }
  "start-one-preview" { Get-GateResult }
  "start-one-gates" { Get-GateResult }
  "start-one-apply" { Get-StartOneApplyResult }
  "one-shot-claim-gate" { Get-OneShotClaimGate }
  "one-shot-executor-gate" { Get-OneShotExecutorGate }
  "worker-route" { Get-RoutePreview }
  "no-start-all" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_no_start_all.v1"; start_all_allowed = $false; blocker = "start_all_forbidden_for_bootstrap_trial_201"; task_created = $false; token_printed = $false } }
  "no-second-task" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_no_second_task.v1"; max_tasks = 1; second_task_allowed = $false; blocker = "max_tasks_1"; task_created = $false; token_printed = $false } }
  "pr-safety" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_pr_safety.v1"; target_branch = "main"; allowed_paths = @("README.md", "docs/**"); max_prs = 1; auto_merge_enabled = $false; raw_transcript_allowed = $false; github_settings_mutation_allowed = $false; token_printed = $false } }
  "evidence" { Get-Evidence }
  "clean-worktree" { [pscustomobject]@{ ok = (Get-GitState).clean; schema = "skybridge.bootstrap_trial_goal201_clean_worktree.v1"; git = Get-GitState; token_printed = $false } }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
