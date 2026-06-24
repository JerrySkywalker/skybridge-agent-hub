[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$TaskId = "live-matlab-golden-task-336-001"
$runnerScript = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$successScript = Join-Path $PSScriptRoot "skybridge-live-matlab-golden-success.ps1"
$outputDir = ".agent/tmp/matlab-golden-trial/success-fixture-smoke"
$fullOutputDir = Join-Path $RepoRoot $outputDir

function Invoke-SuccessScript {
  param([string]$Command, [switch]$Confirm, [string]$ConfirmationText = "")
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $successScript,
    "-Command",
    $Command,
    "-ApiBase",
    $script:WorkerTemplateRunnerApiBase,
    "-WorkerId",
    "jerry-win-local-01",
    "-ProjectId",
    "skybridge-agent-hub",
    "-TaskId",
    $TaskId,
    "-TemplateId",
    "matlab-parameter-sweep.v1",
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
  $fixtureRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command fixture `
    -TaskId $TaskId `
    -WorkerId "jerry-win-local-01" `
    -OutputDir $outputDir `
    -Json
  $fixtureText = ($fixtureRaw | Out-String).Trim()
  Assert-NoUnsafeText $fixtureText
  $fixture = $fixtureText | ConvertFrom-Json
  if ($fixture.ok -ne $true) { throw "Success fixture runner failed." }
  if ($fixture.evidence.validation_status -ne "passed") { throw "Success fixture evidence should pass." }
  if ([int]$fixture.evidence.expected_combination_count -ne 2) { throw "Expected evidence expected_combination_count=2." }
  if ($fixture.evidence.manifest_exists -ne $true) { throw "Expected manifest_exists=true." }
  if ($fixture.evidence.summary_exists -ne $true) { throw "Expected summary_exists=true." }
  if ($fixture.evidence.metrics_exists -ne $true) { throw "Expected metrics_exists=true." }
  if (@($fixture.evidence.changed_files).Count -ne 3) { throw "Success fixture should list exactly three actual output files." }
  if (@($fixture.evidence.expected_outputs_missing).Count -ne 0) { throw "Success fixture should have no missing expected outputs." }
  foreach ($name in @("manifest.json", "summary.json", "metrics.csv")) {
    if (-not (Test-Path -LiteralPath (Join-Path $fullOutputDir $name) -PathType Leaf)) { throw "Missing success fixture output $name." }
  }

  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG336 MATLAB Success Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "matlab")
    labels = @("mg336-fixture", "matlab-success")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg336 success fixture ready"; load = 0 } | Out-Null

  $missingCreateConfirm = Invoke-SuccessScript -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false) { throw "apply-create without confirmation should be rejected." }
  if ([string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing create confirmation reason mismatch." }

  $created = Invoke-SuccessScript -Command "apply-create" -Confirm -ConfirmationText "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY"
  if ($created.ok -ne $true) { throw "Confirmed success fixture task create failed." }
  if ($created.task_created -ne $true) { throw "Expected success fixture task to be created." }

  $previewRun = Invoke-SuccessScript -Command "preview-run"
  if ($previewRun.ok -ne $true) { throw "Success preview-run should select the exact fixture task: $($previewRun.rejected_reason)" }
  if ([int]$previewRun.selected_task_count -ne 1) { throw "Success preview-run should select exactly one task." }
  Assert-False $previewRun.claim_created "preview-run claim_created"
  Assert-False $previewRun.execution_started "preview-run execution_started"

  $missingRunConfirm = Invoke-SuccessScript -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should be rejected." }
  Assert-False $missingRunConfirm.claim_created "missing run confirm claim_created"
  Assert-False $missingRunConfirm.execution_started "missing run confirm execution_started"
  Assert-TokenPrintedFalse $missingRunConfirm

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-golden-success-fixture"
    fixture_outputs_present = $true
    expected_combination_count = 2
    completed_count = [int]$fixture.evidence.completed_count
    failed_count = [int]$fixture.evidence.failed_count
    manifest_exists = [bool]$fixture.evidence.manifest_exists
    summary_exists = [bool]$fixture.evidence.summary_exists
    metrics_exists = [bool]$fixture.evidence.metrics_exists
    task_created = $true
    preview_selected_task_count = [int]$previewRun.selected_task_count
    run_without_confirmation_rejected = $true
    claim_created = $false
    execution_started = $false
    matlab_invoked = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
  if (Test-Path -LiteralPath $fullOutputDir) {
    Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
