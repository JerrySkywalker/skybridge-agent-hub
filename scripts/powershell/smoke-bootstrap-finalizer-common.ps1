[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("pr-merged", "task-file-present", "evidence-safe", "no-raw-artifacts", "no-second-task", "refuses-rerun", "attention-completed", "report-state", "token-printed-false", "clean-worktree")]
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

function New-SmokeStateDir {
  Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal202b-" + [Guid]::NewGuid().ToString("n"))
}

function Write-FinalizerFixtureEvidence {
  param([Parameter(Mandatory = $true)][string]$StateDir)
  New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
  [pscustomobject]@{
    schema = "skybridge.bootstrap_trial_goal201_safe_claim_evidence.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    worker_id = "laptop-zenbookduo"
    lease_id = "bootstrap-trial-201-lease-001"
    allowed_paths = @("README.md", "docs/**")
    prompt_included = $false
    raw_transcript_included = $false
    raw_logs_included = $false
    claim_state = "executed"
    executor_evidence_path = ".agent/tmp/bootstrap-trial-201-one-shot/sanitized-executor-evidence.json"
    pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124"
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "claim-evidence.json") -Encoding UTF8
  [pscustomobject]@{
    schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_evidence.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    worker_id = "laptop-zenbookduo"
    command_class = "codex_exec_sanitized_stdin_discard_output"
    changed_files = @("docs/local-smoke-orientation.md")
    prompt_sha256 = "fixture-prompt-sha"
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    output_persisted = $false
    pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/124"
    auto_merge_enabled = $false
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "sanitized-executor-evidence.json") -Encoding UTF8
  [pscustomobject]@{
    schema = "skybridge.bootstrap_trial_goal202a_start_one_reliability_report.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "trial-report.json") -Encoding UTF8
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
  "pr-merged" {
    $preview = Invoke-Trial -Command finalizer-preview
    if ($preview.state.task_pr.number -ne 124 -or $preview.state.task_pr.merged -ne $true) { throw "PR #124 was not confirmed merged." }
    $preview
  }
  "task-file-present" {
    $preview = Invoke-Trial -Command finalizer-preview
    if ($preview.state.task_file_present -ne $true) { throw "Task file missing on main." }
    $preview
  }
  "evidence-safe" {
    $preview = Invoke-Trial -Command finalizer-preview
    if (@($preview.state.blockers) -contains "executor_evidence_unsafe" -or @($preview.state.blockers) -contains "claim_evidence_unsafe") { throw "Evidence was unsafe." }
    if (-not $preview.state.executor_evidence_hash -or -not $preview.state.claim_evidence_hash) { throw "Evidence hashes missing." }
    $preview
  }
  "no-raw-artifacts" {
    $preview = Invoke-Trial -Command finalizer-preview
    if ($preview.state.no_raw_artifacts -ne $true) { throw "Raw artifact scan failed." }
    $preview
  }
  "no-second-task" {
    $preview = Invoke-Trial -Command finalizer-preview
    if ($preview.state.task_pr_count -ne 1 -or $preview.state.no_second_task -ne $true -or $preview.state.open_task_pr_count -ne 0) { throw "Second task PR guard failed." }
    $preview
  }
  "refuses-rerun" {
    $stateDir = New-SmokeStateDir
    try {
      Write-FinalizerFixtureEvidence -StateDir $stateDir
      $apply = Invoke-Trial -Command finalizer-apply -Extra @("-StateDir", $stateDir)
      if ($apply.final_state -ne "bootstrap_trial_completed") { throw "Finalizer did not complete." }
      $start = Invoke-Trial -Command start-one-preview -Extra @("-StateDir", $stateDir)
      if (@($start.blockers) -notcontains "bootstrap_trial_already_completed" -or $start.would_create_tasks -ne 0) { throw "Start-one rerun was not refused." }
      $executor = Invoke-Trial -Command run-sanitized-executor -Extra @("-Apply", "-StateDir", $stateDir)
      if (@($executor.blockers) -notcontains "bootstrap_trial_already_completed" -or $executor.task_executed -ne $false) { throw "Executor rerun was not refused." }
      [pscustomobject]@{ ok = $true; finalizer = $apply; start_one = $start; executor = $executor; token_printed = $false }
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "attention-completed" {
    $stateDir = New-SmokeStateDir
    try {
      Write-FinalizerFixtureEvidence -StateDir $stateDir
      $apply = Invoke-Trial -Command finalizer-apply -Extra @("-StateDir", $stateDir)
      if ($apply.evidence.attention_event -ne "bootstrap_trial_completed") { throw "Completed attention event missing." }
      $apply
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "report-state" {
    $stateDir = New-SmokeStateDir
    try {
      Write-FinalizerFixtureEvidence -StateDir $stateDir
      $apply = Invoke-Trial -Command finalizer-apply -Extra @("-StateDir", $stateDir)
      $report = Get-Content -Raw -LiteralPath (Join-Path $stateDir "trial-report.json") | ConvertFrom-Json
      if ($report.report_state -ne "bootstrap_trial_completed" -or $report.dashboard.no_next_execution_authorized -ne $true) { throw "Finalizer report state missing." }
      $apply
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "token-printed-false" {
    $preview = Invoke-Trial -Command finalizer-preview
    if ($preview.token_printed -ne $false -or $preview.state.token_printed -ne $false) { throw "Expected token_printed=false." }
    $preview
  }
  "clean-worktree" {
    $before = (git status --short | Out-String).Trim()
    $preview = Invoke-Trial -Command finalizer-preview
    $after = (git status --short | Out-String).Trim()
    if ($before -ne $after) { throw "Finalizer preview mutated the worktree." }
    $preview
  }
}

Assert-SafeJson $result

$summary = [pscustomobject]@{
  ok = $true
  scenario = "bootstrap-finalizer-$Scenario"
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
