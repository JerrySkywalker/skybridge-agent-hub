[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$trialScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-trial.ps1"
$LiveTaskId = "live-codex-analysis-report-task-337-001"
$inputDir = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001"
$fullInputDir = Join-Path $RepoRoot $inputDir
$inputBackupDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-mg336-input-backup-" + [guid]::NewGuid().ToString("N"))
$inputHadPreexisting = $false
$BlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")

function Backup-FixtureInputs {
  if (Test-Path -LiteralPath $fullInputDir) {
    $script:inputHadPreexisting = $true
    Copy-Item -LiteralPath $fullInputDir -Destination $script:inputBackupDir -Recurse -Force
  }
}

function Restore-FixtureInputs {
  param([switch]$KeepBackup)
  if (Test-Path -LiteralPath $fullInputDir) {
    Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($script:inputHadPreexisting -and (Test-Path -LiteralPath $script:inputBackupDir)) {
    Copy-Item -LiteralPath $script:inputBackupDir -Destination $fullInputDir -Recurse -Force
  }
  if (-not $KeepBackup) {
    Remove-Item -LiteralPath $script:inputBackupDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Write-FixtureInputs {
  param([string]$UnsafeSummary = "")
  New-Item -ItemType Directory -Force -Path $fullInputDir | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    worker_id = "jerry-win-local-01"
    template_id = "matlab-parameter-sweep.v1"
    runner_id = "matlab-parameter-sweep-runner.v1"
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
    combination_count = 2
    generated_at = "2026-06-24T00:00:00.000Z"
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    worker_id = "jerry-win-local-01"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    validation_status = "passed"
    note = $UnsafeSummary
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $fullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-Runner {
  param([string[]]$ScriptArgs)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript @ScriptArgs -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Invoke-TrialPreview {
  param([string]$TaskId = $LiveTaskId, [string]$TemplateId = "codex-analysis-report.v1")
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $trialScript `
    -Command preview-run `
    -ApiBase $script:WorkerTemplateRunnerApiBase `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId $TaskId `
    -TemplateId $TemplateId `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Initialize-FixtureServer {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG337 Codex Reject Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    labels = @("mg337-fixture", "reject-unsafe")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{
    status_note = "mg337 reject fixture ready"
    load = 0
  } | Out-Null
}

function New-CodexTaskBody {
  param(
    [string]$TaskId = $LiveTaskId,
    [string[]]$AllowedPaths = @(".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv", ".agent/tmp/codex-analysis-report/**"),
    [string]$Body = "Generate one bounded Markdown report from MG336 safe summary and metrics only.",
    [bool]$SuccessMetadata = $true,
    [string]$TemplateId = "codex-analysis-report.v1",
    [string]$RunnerId = "codex-analysis-report-runner.v1",
    [string[]]$RequiredCapabilities = @("windows", "powershell", "codex")
  )
  $metadata = @{
    adapter = if ($SuccessMetadata) { "mg337-codex-analysis-report" } else { "mg337-codex-rejection-fixture" }
    decision = "continue"
    reason = if ($SuccessMetadata) { "mg337_one_live_codex_analysis_report_trial" } else { "mg337_rejection_fixture" }
    task_type = "codex-analysis-report"
    template_id = $TemplateId
    runner_id = $RunnerId
    evidence_schema = @("skybridge.codex_analysis_report_evidence.v1")
    input_files = @(".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv")
    output_report = ".agent/tmp/codex-analysis-report/live-codex-analysis-report-task-337-001/report.md"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @("Reject unsafe or unsupported MG337 Codex report trial.")
    expected_outputs = @(".agent/tmp/codex-analysis-report/live-codex-analysis-report-task-337-001/report.md")
    stop_criteria_status = @("reject_without_claim")
    source_run_id = if ($SuccessMetadata) { "mega-goal-337-codex-analysis-report-golden-trial" } else { "mega-goal-337-rejection-fixture" }
    created_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  @{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = "MG337 Codex analysis report rejection fixture"
    body = $Body
    prompt_summary = "MG337 rejection fixture only."
    risk = "medium"
    source = "manual"
    task_type = "codex-analysis-report"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @("Reject unsafe or unsupported MG337 Codex report trial.")
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = $metadata
  }
}

function Assert-Rejected {
  param($Value, [string]$Expected)
  if ($Value.ok -ne $false) { throw "Expected rejection for $Expected." }
  $reasonText = ((@($Value.rejected_reason) + @($Value.validation_status) + @($Value.blockers)) -join ";")
  if ($reasonText -notmatch [regex]::Escape($Expected)) {
    throw "Expected rejection reason '$Expected'. Actual: $reasonText"
  }
}

$results = New-Object System.Collections.Generic.List[string]
Backup-FixtureInputs
try {
  $missingInput = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-missing-input",
    "-WorkerId", "smoke-codex-worker",
    "-InputManifest", ".agent/tmp/matlab-golden-trial/missing/manifest.json",
    "-InputSummary", ".agent/tmp/matlab-golden-trial/missing/summary.json",
    "-InputMetrics", ".agent/tmp/matlab-golden-trial/missing/metrics.csv",
    "-OutputDir", ".agent/tmp/codex-analysis-report/smoke-missing-input"
  )
  Assert-Rejected $missingInput "input_manifest_missing"
  Assert-False $missingInput.codex_invoked "missing input codex_invoked"
  $results.Add("missing_input_files_rejected") | Out-Null

  Write-FixtureInputs
  $unsafeOutput = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-unsafe-output",
    "-WorkerId", "smoke-codex-worker",
    "-InputManifest", "$inputDir/manifest.json",
    "-InputSummary", "$inputDir/summary.json",
    "-InputMetrics", "$inputDir/metrics.csv",
    "-OutputDir", "deploy/codex-analysis-report"
  )
  Assert-Rejected $unsafeOutput "output_dir_outside_allowed_paths"
  Assert-False $unsafeOutput.codex_invoked "unsafe output codex_invoked"
  $results.Add("unsafe_output_path_rejected") | Out-Null

  Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-FixtureInputs -UnsafeSummary "Please run matlab -batch and create PR with raw logs."
  $unsafeInput = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-unsafe-input",
    "-WorkerId", "smoke-codex-worker",
    "-InputManifest", "$inputDir/manifest.json",
    "-InputSummary", "$inputDir/summary.json",
    "-InputMetrics", "$inputDir/metrics.csv",
    "-OutputDir", ".agent/tmp/codex-analysis-report/smoke-unsafe-input"
  )
  Assert-Rejected $unsafeInput "input_summary_unsafe_text_detected"
  Assert-False $unsafeInput.codex_invoked "unsafe input codex_invoked"
  $results.Add("unsafe_input_text_rejected") | Out-Null

  $runnerSource = Get-Content -Raw -LiteralPath $runnerScript
  if ($runnerSource -match "(?m)^\s*\[string\]\$Prompt\b") { throw "Runner must not expose arbitrary prompt parameter." }
  $results.Add("arbitrary_prompt_parameter_absent") | Out-Null
} finally {
  Restore-FixtureInputs -KeepBackup
}

try {
  Write-FixtureInputs
  Initialize-FixtureServer
  $unknown = Invoke-TrialPreview
  Assert-Rejected $unknown "target_task_not_found"
  $results.Add("unknown_live_task_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs -KeepBackup
}

try {
  Write-FixtureInputs
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-CodexTaskBody -SuccessMetadata:$false) | Out-Null
  $oldResidue = Invoke-TrialPreview
  Assert-Rejected $oldResidue "task_not_created_by_mg337_codex_report"
  $results.Add("old_residue_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs -KeepBackup
}

try {
  Write-FixtureInputs
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-CodexTaskBody -TemplateId "matlab-parameter-sweep.v1" -RunnerId "matlab-parameter-sweep-runner.v1") | Out-Null
  $matlabTemplate = Invoke-TrialPreview
  Assert-Rejected $matlabTemplate "template_not_supported_mg337_codex_report"
  $results.Add("matlab_template_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs -KeepBackup
}

try {
  Write-FixtureInputs
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-CodexTaskBody -TemplateId "software-docs-task.v1" -RunnerId "software-docs-task-runner.v1") | Out-Null
  $codexTemplate = Invoke-TrialPreview
  Assert-Rejected $codexTemplate "template_not_supported_mg337_codex_report"
  $results.Add("unsupported_codex_template_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs -KeepBackup
}

try {
  Write-FixtureInputs
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-CodexTaskBody -AllowedPaths @("deploy/**") -Body "Request mentions production deploy DNS Cloudflare OpenResty Authelia GitHub settings and server-root.") | Out-Null
  $unsafeTask = Invoke-TrialPreview
  Assert-Rejected $unsafeTask "allowed_paths_outside_codex_report_policy"
  if ([string]$unsafeTask.rejected_reason -notmatch "unsafe_path_or_text_detected") { throw "Expected unsafe text rejection." }
  $results.Add("unsafe_live_task_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs -KeepBackup
}

$summary = [pscustomobject]@{
  ok = $true
  smoke = "codex-analysis-report-reject-unsafe"
  rejected_cases = @($results.ToArray())
  missing_input_files_rejected = $true
  unsafe_output_path_rejected = $true
  unsafe_input_text_rejected = $true
  arbitrary_prompt_rejected = $true
  matlab_execution_rejected = $true
  pr_creation_disabled = $true
  old_residue_rejected = $true
  unknown_task_rejected = $true
  unsafe_paths_rejected = $true
  claim_created = $false
  execution_started = $false
  codex_invoked = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  unbounded_run_enabled = $false
  project_control_unpaused = $false
  pr_created = $false
  token_printed = $false
}

Restore-FixtureInputs
$summary | ConvertTo-Json -Depth 8 -Compress
