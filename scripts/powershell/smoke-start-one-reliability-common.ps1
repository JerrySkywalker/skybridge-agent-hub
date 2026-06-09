[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("existing-task-pr-detected", "refuses-duplicate-execution", "refuses-duplicate-claim", "human-review-hold", "pr-ci-summary", "no-raw-ci-logs", "attention-event", "dashboard-state", "trial-report", "no-second-task", "no-auto-merge")]
  [string]$Scenario,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "skybridge-bootstrap-trial-goal201.ps1"

function Invoke-Trial {
  param([string]$Command, [string[]]$Extra = @())
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Command $Command -SimulateExistingOpenTaskPr @Extra -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
  $output | ConvertFrom-Json
}

function New-SmokeStateDir {
  Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-goal202a-" + [Guid]::NewGuid().ToString("n"))
}

function Write-OwnedClaimEvidence {
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
    claim_state = "resumable_owned_claim"
    executor_evidence_path = $null
    pr_url = $null
    prompt_included = $false
    raw_transcript_included = $false
    raw_logs_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $StateDir "claim-evidence.json") -Encoding UTF8
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
  "existing-task-pr-detected" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if (-not $report.task_pr.exists) { throw "Existing task PR was not detected." }
    if (-not $report.duplicate_run_prevention.existing_open_task_pr_for_bootstrap_trial) { throw "Existing PR duplicate guard missing." }
    $report
  }
  "refuses-duplicate-execution" {
    $stateDir = New-SmokeStateDir
    try {
      Write-OwnedClaimEvidence -StateDir $stateDir
      $executor = Invoke-Trial -Command run-sanitized-executor -Extra @("-Apply", "-StateDir", $stateDir)
      if ($executor.ok -or @($executor.blockers) -notcontains "existing_open_task_pr_for_bootstrap_trial") { throw "Executor did not refuse duplicate execution." }
      if ($executor.final_state -ne "held_waiting_human_pr_review") { throw "Executor did not hold for human review." }
      $executor
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "refuses-duplicate-claim" {
    $stateDir = New-SmokeStateDir
    try {
      $claim = Invoke-Trial -Command one-shot-claim-gate -Extra @("-Apply", "-StateDir", $stateDir)
      if ($claim.ok -or @($claim.blockers) -notcontains "existing_open_task_pr_for_bootstrap_trial") { throw "Claim gate did not refuse duplicate claim." }
      if ($claim.task_created -or $claim.lease_created) { throw "Duplicate claim path created work." }
      $claim
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "human-review-hold" {
    $preview = Invoke-Trial -Command start-one-preview
    if ($preview.dashboard_state -ne "held_waiting_human_pr_review") { throw "Preview did not report human review hold." }
    if (@($preview.blockers) -notcontains "existing_open_task_pr_for_bootstrap_trial") { throw "Preview missing existing PR blocker." }
    $preview
  }
  "pr-ci-summary" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($report.dashboard.checks_status -notin @("pending", "success", "failure", "error", "cancelled", "skipped", "unknown")) { throw "Unexpected check status." }
    $report
  }
  "no-raw-ci-logs" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($report.evidence.raw_ci_logs_persisted -ne $false -or $report.task_pr.raw_ci_logs_persisted -ne $false) { throw "Raw CI logs were persisted." }
    $report
  }
  "attention-event" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($report.attention_event -ne "human_pr_review_required") { throw "Attention event missing." }
    $report
  }
  "dashboard-state" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($report.dashboard.waiting_for_human_review -ne $true -or $report.report_state -ne "held_waiting_human_pr_review") { throw "Dashboard hold state missing." }
    $report
  }
  "trial-report" {
    $stateDir = New-SmokeStateDir
    try {
      $report = Invoke-Trial -Command start-one-reliability-report -Extra @("-Apply", "-StateDir", $stateDir)
      $path = Join-Path $stateDir "trial-report.json"
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Trial report was not written." }
      $saved = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
      if ($saved.report_state -ne "held_waiting_human_pr_review" -or $saved.token_printed -ne $false) { throw "Unexpected trial report state." }
      $report
    } finally {
      Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
  "no-second-task" {
    $preview = Invoke-Trial -Command start-one-preview
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($preview.would_create_tasks -ne 0 -or -not $report.duplicate_run_prevention.no_second_task -or -not $report.duplicate_run_prevention.no_second_task_pr) { throw "Second task prevention missing." }
    $report
  }
  "no-auto-merge" {
    $report = Invoke-Trial -Command start-one-reliability-report
    if ($report.no_auto_merge -ne $true -or $report.dashboard.no_auto_merge -ne $true -or $report.task_pr.auto_merge_enabled -ne $false) { throw "Auto-merge was not disabled." }
    $report
  }
}

Assert-SafeJson $result

$summary = [pscustomobject]@{
  ok = $true
  scenario = "start-one-reliability-$Scenario"
  result = $result
  task_created = $false
  task_claimed = $false
  task_executed = $false
  pr_created = $false
  auto_merge_enabled = $false
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 100 -Compress } else { $summary | Format-List }
