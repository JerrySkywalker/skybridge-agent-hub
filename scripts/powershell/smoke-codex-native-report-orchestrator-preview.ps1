[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$nativeScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-native-success.ps1"
$taskId = "live-codex-analysis-report-task-339-001"
$inputDir = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001"
$outputDir = ".agent/tmp/codex-analysis-report/$taskId"
$fullInputDir = Join-Path $RepoRoot $inputDir
$fullOutputDir = Join-Path $RepoRoot $outputDir
$inputBackupDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-mg336-input-backup-" + [guid]::NewGuid().ToString("N"))
$outputBackupDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-mg339-output-backup-" + [guid]::NewGuid().ToString("N"))
$inputHadPreexisting = $false
$outputHadPreexisting = $false
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

function Backup-OutputArtifact {
  if (Test-Path -LiteralPath $fullOutputDir) {
    $script:outputHadPreexisting = $true
    Copy-Item -LiteralPath $fullOutputDir -Destination $script:outputBackupDir -Recurse -Force
  }
}

function Restore-OutputArtifact {
  if (Test-Path -LiteralPath $fullOutputDir) {
    Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($script:outputHadPreexisting -and (Test-Path -LiteralPath $script:outputBackupDir)) {
    Copy-Item -LiteralPath $script:outputBackupDir -Destination $fullOutputDir -Recurse -Force
  }
  Remove-Item -LiteralPath $script:outputBackupDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Write-FixtureInputs {
  New-Item -ItemType Directory -Force -Path $fullInputDir | Out-Null
  @{
    schema = "skybridge.matlab_sweep_manifest.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    parameter_grid_summary = "eta=[2,3]; h_km=[500]; P=[6]; combinations=2"
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "manifest.json") -Encoding UTF8
  @{
    schema = "skybridge.matlab_sweep_summary.v1"
    task_id = "live-matlab-golden-task-336-001"
    combination_count = 2
    completed_count = 2
    failed_count = 0
    validation_status = "passed"
    token_printed = $false
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $fullInputDir "summary.json") -Encoding UTF8
  @("eta,h_km,P,score", "2,500,6,0.024", "3,500,6,0.036") | Set-Content -LiteralPath (Join-Path $fullInputDir "metrics.csv") -Encoding UTF8
}

function Invoke-Native {
  param([string]$Command, [switch]$Confirm, [string]$ConfirmationText = "")
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $nativeScript,
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
  Backup-OutputArtifact
  Write-FixtureInputs
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $fakeCodexDir | Out-Null
  "@echo off`r`nexit /b 0`r`n" | Set-Content -LiteralPath (Join-Path $fakeCodexDir "codex.cmd") -Encoding ASCII
  $env:PATH = "$fakeCodexDir;$oldPath"

  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG339 Codex Native Report Preview"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    labels = @("mg339-fixture", "codex-native-report")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg339 preview ready"; load = 0 } | Out-Null

  $previewCreate = Invoke-Native -Command "preview-create"
  if ($previewCreate.ok -ne $true) { throw "preview-create should be ok: $($previewCreate.blockers -join ';')" }
  if ($previewCreate.task_created -ne $false) { throw "preview-create must not create a task." }
  if ($previewCreate.claim_created -ne $false -or $previewCreate.execution_started -ne $false) { throw "preview-create must not claim/start." }

  $missingCreateConfirm = Invoke-Native -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false -or [string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "apply-create without confirmation should reject." }

  $created = Invoke-Native -Command "apply-create" -Confirm -ConfirmationText "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_NATIVE_REPORT_TASK_ONLY"
  if ($created.ok -ne $true -or $created.task_created -ne $true) { throw "Confirmed MG339 native task create failed." }

  $previewRun = Invoke-Native -Command "preview-run"
  if ($previewRun.ok -ne $true) { throw "preview-run should select exact native task: $($previewRun.rejected_reason)" }
  if ([int]$previewRun.selected_task_count -ne 1) { throw "preview-run should select exactly one task." }
  if ($previewRun.claim_created -ne $false -or $previewRun.execution_started -ne $false) { throw "preview-run must not claim/start." }

  $missingRunConfirm = Invoke-Native -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should reject." }
  if ($missingRunConfirm.claim_created -ne $false -or $missingRunConfirm.execution_started -ne $false) { throw "missing run confirmation must not claim/start." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-native-report-orchestrator-preview"
    preview_create_would_create_task = [bool]$previewCreate.would_create_task
    confirmed_create_created_task = [bool]$created.task_created
    preview_selected_task_count = [int]$previewRun.selected_task_count
    preview_run_claim_created = $false
    missing_run_confirmation_rejected = $true
    final_report_source = "none"
    fallback_report_used = $false
    native_report_valid = $false
    claim_created = $false
    execution_started = $false
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
  Restore-OutputArtifact
  Remove-Item -LiteralPath $fakeCodexDir -Recurse -Force -ErrorAction SilentlyContinue
}
