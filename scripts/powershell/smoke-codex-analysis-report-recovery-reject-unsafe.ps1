[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$recoveryScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-recovery.ps1"
$taskId = "live-codex-analysis-report-task-338-001"
$oldTaskId = "live-codex-analysis-report-task-337-001"
$inputDir = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001"
$fullInputDir = Join-Path $RepoRoot $inputDir
$inputBackupDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-mg336-input-backup-" + [guid]::NewGuid().ToString("N"))
$inputHadPreexisting = $false

function Backup-FixtureInputs {
  if (Test-Path -LiteralPath $fullInputDir) {
    $script:inputHadPreexisting = $true
    Copy-Item -LiteralPath $fullInputDir -Destination $script:inputBackupDir -Recurse -Force
  }
}

function Restore-FixtureInputs {
  if (Test-Path -LiteralPath $fullInputDir) {
    Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($script:inputHadPreexisting -and (Test-Path -LiteralPath $script:inputBackupDir)) {
    Copy-Item -LiteralPath $script:inputBackupDir -Destination $fullInputDir -Recurse -Force
  }
  Remove-Item -LiteralPath $script:inputBackupDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Write-FixtureInputs {
  New-Item -ItemType Directory -Force -Path $fullInputDir | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    validation_status = "passed"
    raw_stdout_included = $false
    raw_stderr_included = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $fullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-Recovery {
  param([string]$Command, [string]$RequestedTaskId = $taskId)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $recoveryScript `
    -Command $Command `
    -ApiBase $script:WorkerTemplateRunnerApiBase `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId $RequestedTaskId `
    -TemplateId "codex-analysis-report.v1" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function New-TaskBody {
  param([string]$RequestedTaskId, [bool]$SuccessMetadata = $true, [string[]]$AllowedPaths = @(".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json", ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv", ".agent/tmp/codex-analysis-report/**"))
  @{
    task_id = $RequestedTaskId
    project_id = "skybridge-agent-hub"
    title = "MG338 rejection fixture"
    body = "Generate one bounded Markdown report from safe MG336 outputs only."
    prompt_summary = "MG338 rejection fixture only."
    risk = "medium"
    source = "manual"
    task_type = "codex-analysis-report"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @(".env", "secrets/**", "deploy/**", ".git/**")
    validation = @("Reject unsafe or unsupported MG338 recovery trial.")
    required_capabilities = @("windows", "powershell", "codex")
    planner_metadata = @{
      adapter = if ($SuccessMetadata) { "mg338-codex-artifact-persistence-recovery" } else { "mg337-codex-analysis-report" }
      decision = "continue"
      reason = if ($SuccessMetadata) { "mg338_one_live_codex_report_recovery_task" } else { "mg337_one_live_codex_analysis_report_trial" }
      task_type = "codex-analysis-report"
      template_id = "codex-analysis-report.v1"
      runner_id = "codex-analysis-report-runner.v1"
      output_report = ".agent/tmp/codex-analysis-report/$RequestedTaskId/report.md"
      expected_outputs = @(".agent/tmp/codex-analysis-report/$RequestedTaskId/report.md")
      source_run_id = if ($SuccessMetadata) { "mega-goal-338-codex-artifact-persistence-recovery" } else { "mega-goal-337-codex-analysis-report-golden-trial" }
    }
  }
}

try {
  Backup-FixtureInputs
  Write-FixtureInputs
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG338 Reject Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg338 reject ready"; load = 0 } | Out-Null

  $missingCreateConfirm = Invoke-Recovery -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false -or [string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing create confirmation should reject." }

  $oldPreview = Invoke-Recovery -Command "preview-run" -RequestedTaskId $oldTaskId
  if ($oldPreview.ok -ne $false -or [string]$oldPreview.rejected_reason -notmatch "old_task_reuse_refused") { throw "Old task id should be refused." }

  $unsafeOutput = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command preview `
    -TaskId $taskId `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$inputDir/manifest.json" `
    -InputSummary "$inputDir/summary.json" `
    -InputMetrics "$inputDir/metrics.csv" `
    -OutputDir "deploy/codex-analysis-report" `
    -Json
  $unsafe = (($unsafeOutput | Out-String).Trim() | ConvertFrom-Json)
  if ($unsafe.ok -ne $false -or ((@($unsafe.blockers) -join ";") -notmatch "output_path_invalid")) { throw "Unsafe output path should reject." }

  Remove-Item -LiteralPath $fullInputDir -Recurse -Force -ErrorAction SilentlyContinue
  $missingInput = Invoke-Recovery -Command "preview-create"
  if ($missingInput.ok -ne $false -or ((@($missingInput.blockers) -join ";") -notmatch "mg336_input_files_missing")) { throw "Missing inputs should reject." }

  Write-FixtureInputs
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-TaskBody -RequestedTaskId $taskId -SuccessMetadata:$false) | Out-Null
  $oldResidue = Invoke-Recovery -Command "preview-run"
  if ($oldResidue.ok -ne $false -or [string]$oldResidue.rejected_reason -notmatch "task_not_created_by_mg338_codex_artifact_recovery") { throw "Old metadata residue should reject." }

  $runnerSource = Get-Content -Raw -LiteralPath $runnerScript
  if ($runnerSource -match "(?m)^\s*\[string\]\$Prompt\b") { throw "Runner must not expose arbitrary prompt parameter." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-recovery-reject-unsafe"
    create_without_confirmation_rejected = $true
    run_without_exact_task_rejected = $true
    old_task_reuse_rejected = $true
    missing_input_files_rejected = $true
    unsafe_output_path_rejected = $true
    arbitrary_prompt_rejected = $true
    claim_created = $false
    execution_started = $false
    codex_invoked = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs
}
