[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-codex-analysis-report-runner.ps1"
$trialScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-trial.ps1"
$taskId = "live-codex-analysis-report-task-337-001"
$inputDir = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001"
$outputDir = ".agent/tmp/codex-analysis-report/$taskId"
$fullInputDir = Join-Path $RepoRoot $inputDir
$fullOutputDir = Join-Path $RepoRoot $outputDir
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
    min_score = 0.024
    max_score = 0.036
    mean_score = 0.03
    validation_status = "passed"
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

function Invoke-Trial {
  param([string]$Command, [switch]$Confirm, [string]$ConfirmationText = "")
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $trialScript,
    "-Command",
    $Command,
    "-ApiBase",
    $script:WorkerTemplateRunnerApiBase,
    "-WorkerId",
    "jerry-win-local-01",
    "-ProjectId",
    "skybridge-agent-hub",
    "-TaskId",
    $taskId,
    "-TemplateId",
    "codex-analysis-report.v1",
    "-Json"
  )
  if ($Confirm) { $args += "-Confirm" }
  if (-not [string]::IsNullOrWhiteSpace($ConfirmationText)) { $args += @("-ConfirmationText", $ConfirmationText) }
  $raw = & pwsh @args
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Backup-FixtureInputs
  Write-FixtureInputs
  $fixtureRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command fixture `
    -TaskId $taskId `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$inputDir/manifest.json" `
    -InputSummary "$inputDir/summary.json" `
    -InputMetrics "$inputDir/metrics.csv" `
    -OutputDir $outputDir `
    -Json
  $fixtureText = ($fixtureRaw | Out-String).Trim()
  Assert-NoUnsafeText $fixtureText
  $fixture = $fixtureText | ConvertFrom-Json
  if ($fixture.ok -ne $true) { throw "Codex report fixture runner failed." }
  if ($fixture.evidence.validation_status -ne "passed") { throw "Fixture evidence should pass." }
  if ($fixture.evidence.report_exists -ne $true) { throw "Fixture report_exists should be true." }
  if (@($fixture.evidence.changed_files).Count -ne 1) { throw "Fixture should list exactly one report file." }
  $reportPath = Join-Path $fullOutputDir "report.md"
  if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) { throw "Missing report.md." }
  $reportText = Get-Content -Raw -LiteralPath $reportPath
  Assert-NoUnsafeText $reportText
  if ($reportText -notmatch "(?i)synthetic runner validation") { throw "Report must state synthetic runner validation." }
  Assert-False $fixture.evidence.codex_invoked "fixture evidence codex_invoked"
  Assert-False $fixture.evidence.raw_codex_log_included "fixture raw_codex_log_included"
  Assert-False $fixture.evidence.raw_prompt_included "fixture raw_prompt_included"
  Assert-False $fixture.evidence.matlab_run_called "fixture matlab_run_called"
  Assert-TokenPrintedFalse $fixture.evidence

  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG337 Codex Analysis Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    labels = @("mg337-fixture", "codex-report")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg337 fixture ready"; load = 0 } | Out-Null

  $missingCreateConfirm = Invoke-Trial -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false) { throw "apply-create without confirmation should be rejected." }
  if ([string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing create confirmation reason mismatch." }

  $created = Invoke-Trial -Command "apply-create" -Confirm -ConfirmationText "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_ANALYSIS_REPORT_TASK_ONLY"
  if ($created.ok -ne $true) { throw "Confirmed codex report task create failed." }
  if ($created.task_created -ne $true) { throw "Expected fixture task to be created." }

  $previewRun = Invoke-Trial -Command "preview-run"
  if ($previewRun.ok -ne $true) { throw "preview-run should select exact task: $($previewRun.rejected_reason)" }
  if ([int]$previewRun.selected_task_count -ne 1) { throw "preview-run should select exactly one task." }
  Assert-False $previewRun.claim_created "preview-run claim_created"
  Assert-False $previewRun.execution_started "preview-run execution_started"

  $missingRunConfirm = Invoke-Trial -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should be rejected." }
  Assert-False $missingRunConfirm.claim_created "missing run confirm claim_created"
  Assert-False $missingRunConfirm.execution_started "missing run confirm execution_started"
  Assert-TokenPrintedFalse $missingRunConfirm

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-fixture"
    report_exists = $true
    changed_files_count = @($fixture.evidence.changed_files).Count
    task_created = $true
    preview_selected_task_count = [int]$previewRun.selected_task_count
    run_without_confirmation_rejected = $true
    claim_created = $false
    execution_started = $false
    codex_invoked = $false
    matlab_run_called = $false
    raw_codex_log_included = $false
    raw_prompt_included = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
