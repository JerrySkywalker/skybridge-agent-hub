[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$recoveryScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-recovery.ps1"
$taskId = "live-codex-analysis-report-task-338-001"
$inputDir = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001"
$outputDir = ".agent/tmp/codex-analysis-report/$taskId"
$fullInputDir = Join-Path $RepoRoot $inputDir
$fullOutputDir = Join-Path $RepoRoot $outputDir
$inputBackupDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-mg336-input-backup-" + [guid]::NewGuid().ToString("N"))
$inputHadPreexisting = $false
$fakeCodexDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-fake-codex-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH

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
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
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
  param([string]$Command, [switch]$Confirm, [string]$ConfirmationText = "")
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $recoveryScript,
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
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $fakeCodexDir | Out-Null
  "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.cmd") -Encoding ASCII
  $env:PATH = "$fakeCodexDir;$oldPath"

  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG338 Codex Artifact Recovery Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    labels = @("mg338-fixture", "codex-artifact-recovery")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg338 fixture ready"; load = 0 } | Out-Null

  $missingCreateConfirm = Invoke-Recovery -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false -or [string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "apply-create without confirmation should reject." }

  $created = Invoke-Recovery -Command "apply-create" -Confirm -ConfirmationText "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY"
  if ($created.ok -ne $true -or $created.task_created -ne $true) { throw "Confirmed recovery task create failed." }

  $previewRun = Invoke-Recovery -Command "preview-run"
  if ($previewRun.ok -ne $true) { throw "preview-run should select exact recovery task: $($previewRun.rejected_reason)" }
  if ([int]$previewRun.selected_task_count -ne 1) { throw "preview-run should select exactly one task." }
  if ($previewRun.claim_created -ne $false -or $previewRun.execution_started -ne $false) { throw "preview-run must not claim/start." }

  $missingRunConfirm = Invoke-Recovery -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should reject." }
  if ($missingRunConfirm.claim_created -ne $false -or $missingRunConfirm.execution_started -ne $false) { throw "missing confirmation must not claim/start." }

  $apply = Invoke-Recovery -Command "apply-run" -Confirm -ConfirmationText "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY"
  if ($apply.ok -ne $true) { throw "Confirmed recovery apply failed: $($apply.runner_result.rejected_reason)" }
  if ($apply.task_claimed_count -ne 1) { throw "apply-run should claim exactly one task." }
  if ($apply.old_task_claimed -ne $false) { throw "old task must not be claimed." }
  if ($apply.runner_result.final_task_state -ne "completed") { throw "Final task state should be completed." }
  if ($apply.runner_result.validation_status -ne "passed") { throw "Evidence validation should pass." }
  if ($apply.runner_result.report_exists -ne $true) { throw "Report should exist." }
  if ([int64]$apply.runner_result.report_size_bytes -le 0) { throw "Report should be non-empty." }
  if ($apply.runner_result.fallback_report_used -ne $true) { throw "Fixture should use fallback writer." }
  if (@($apply.runner_result.changed_files).Count -ne 1) { throw "Expected exactly one changed file." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-recovery-fixture"
    task_created = $true
    preview_selected_task_count = [int]$previewRun.selected_task_count
    task_claimed_count = [int]$apply.task_claimed_count
    final_task_state = [string]$apply.runner_result.final_task_state
    report_exists = [bool]$apply.runner_result.report_exists
    report_size_bytes = [int64]$apply.runner_result.report_size_bytes
    fallback_report_used = [bool]$apply.runner_result.fallback_report_used
    validation_status = [string]$apply.runner_result.validation_status
    changed_files = @($apply.runner_result.changed_files)
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  $env:PATH = $oldPath
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $fakeCodexDir -Recurse -Force -ErrorAction SilentlyContinue
}
