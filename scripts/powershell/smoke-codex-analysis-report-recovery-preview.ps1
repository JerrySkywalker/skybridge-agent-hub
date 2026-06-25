[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$recoveryScript = Join-Path $PSScriptRoot "skybridge-live-codex-analysis-report-recovery.ps1"
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
  param([string]$Command)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $recoveryScript `
    -Command $Command `
    -ApiBase $script:WorkerTemplateRunnerApiBase `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId "live-codex-analysis-report-task-338-001" `
    -TemplateId "codex-analysis-report.v1" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Backup-FixtureInputs
  Write-FixtureInputs
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG338 Codex Artifact Recovery Preview"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "codex")
    labels = @("mg338-fixture", "codex-artifact-recovery")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg338 preview ready"; load = 0 } | Out-Null

  $previewCreate = Invoke-Recovery -Command "preview-create"
  if ($previewCreate.ok -ne $true) { throw "preview-create should be ok: $($previewCreate.blockers -join ';')" }
  if ($previewCreate.task_created -ne $false) { throw "preview-create must not create task." }
  if ($previewCreate.claim_created -ne $false) { throw "preview-create must not claim." }

  $previewRun = Invoke-Recovery -Command "preview-run"
  if ($previewRun.ok -ne $false) { throw "preview-run should reject before task exists." }
  if ([string]$previewRun.rejected_reason -notmatch "target_task_not_found") { throw "preview-run rejection mismatch: $($previewRun.rejected_reason)" }
  if ($previewRun.claim_created -ne $false) { throw "preview-run must not claim." }
  if ($previewRun.execution_started -ne $false) { throw "preview-run must not start." }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-analysis-report-recovery-preview"
    preview_create_would_create_task = [bool]$previewCreate.would_create_task
    preview_run_rejected_without_task = $true
    claim_created = $false
    execution_started = $false
    matlab_run_called = $false
    worker_loop_started = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  Restore-FixtureInputs
}
