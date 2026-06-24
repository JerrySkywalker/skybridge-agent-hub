[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$TaskId = "live-matlab-golden-task-334-001"
$runnerScript = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$recoveryScript = Join-Path $PSScriptRoot "skybridge-live-matlab-golden-recovery.ps1"
$outputDir = ".agent/tmp/matlab-golden-trial/recovery-fixture-smoke"
$fullOutputDir = Join-Path $RepoRoot $outputDir

function Invoke-RecoveryScript {
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
  if ($fixture.ok -ne $true) { throw "Recovery fixture runner failed." }
  if ($fixture.evidence.validation_status -ne "passed") { throw "Recovery fixture evidence should pass." }
  if (@($fixture.evidence.changed_files).Count -ne 3) { throw "Recovery fixture should list exactly three actual output files." }
  if (@($fixture.evidence.expected_outputs_missing).Count -ne 0) { throw "Recovery fixture should have no missing expected outputs." }
  foreach ($name in @("manifest.json", "summary.json", "metrics.csv")) {
    if (-not (Test-Path -LiteralPath (Join-Path $fullOutputDir $name) -PathType Leaf)) { throw "Missing recovery fixture output $name." }
  }

  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG334 MATLAB Recovery Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "matlab")
    labels = @("mg334-fixture", "matlab-recovery")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{ status_note = "mg334 recovery fixture ready"; load = 0 } | Out-Null

  $missingCreateConfirm = Invoke-RecoveryScript -Command "apply-create"
  if ($missingCreateConfirm.ok -ne $false) { throw "apply-create without confirmation should be rejected." }
  if ([string]$missingCreateConfirm.review_reason -ne "missing_exact_confirmation") { throw "Missing create confirmation reason mismatch." }

  $created = Invoke-RecoveryScript -Command "apply-create" -Confirm -ConfirmationText "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY"
  if ($created.ok -ne $true) { throw "Confirmed recovery fixture task create failed." }
  if ($created.task_created -ne $true) { throw "Expected recovery fixture task to be created." }

  $missingRunConfirm = Invoke-RecoveryScript -Command "apply-run"
  if ($missingRunConfirm.ok -ne $false) { throw "apply-run without confirmation should be rejected." }
  Assert-False $missingRunConfirm.claim_created "missing run confirm claim_created"
  Assert-False $missingRunConfirm.execution_started "missing run confirm execution_started"
  Assert-TokenPrintedFalse $missingRunConfirm

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-recovery-fixture"
    fixture_outputs_present = $true
    task_created = $true
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
