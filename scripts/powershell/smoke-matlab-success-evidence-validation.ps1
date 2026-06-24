[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$successTaskId = "smoke-matlab-success-evidence-" + [Guid]::NewGuid().ToString("n")
$successOutputDir = ".agent/tmp/matlab-golden-trial/$successTaskId"
$successFullOutputDir = Join-Path $RepoRoot $successOutputDir
$failureTaskId = "smoke-matlab-success-failure-" + [Guid]::NewGuid().ToString("n")
$failureOutputDir = ".agent/tmp/matlab-golden-trial/$failureTaskId"
$failureFullOutputDir = Join-Path $RepoRoot $failureOutputDir
$runnerScript = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-fake-matlab-success-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
$oldMatlabExe = $env:SKYBRIDGE_MATLAB_EXE

try {
  $successRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command fixture `
    -TaskId $successTaskId `
    -WorkerId "smoke-matlab-worker" `
    -OutputDir $successOutputDir `
    -Json
  $successText = ($successRaw | Out-String).Trim()
  Assert-NoUnsafeText $successText
  $success = $successText | ConvertFrom-Json
  if ($success.ok -ne $true) { throw "Fixture success output failed." }
  if ($success.evidence.ok -ne $true) { throw "Success evidence ok should be true." }
  if ([int]$success.evidence.expected_combination_count -ne 2) { throw "Success evidence expected_combination_count mismatch." }
  if ($success.evidence.manifest_exists -ne $true) { throw "Success evidence manifest_exists mismatch." }
  if ($success.evidence.summary_exists -ne $true) { throw "Success evidence summary_exists mismatch." }
  if ($success.evidence.metrics_exists -ne $true) { throw "Success evidence metrics_exists mismatch." }
  if (@($success.evidence.changed_files).Count -ne 3) { throw "Success evidence should list exactly three changed files." }
  foreach ($relative in @($success.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Success evidence listed nonexistent file: $relative" }
  }
  $metricsLines = @(Get-Content -LiteralPath (Join-Path $successFullOutputDir "metrics.csv") | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($metricsLines.Count -ne 3) { throw "Expected metrics header plus two combinations." }
  Assert-False $success.evidence.raw_stdout_included "success evidence raw_stdout_included"
  Assert-False $success.evidence.raw_stderr_included "success evidence raw_stderr_included"
  Assert-TokenPrintedFalse $success.evidence

  New-Item -ItemType Directory -Path $tempDir | Out-Null
  if ($IsWindows) {
    $fakePath = Join-Path $tempDir "matlab.cmd"
    Set-Content -LiteralPath $fakePath -Value "@echo off`r`nexit /b 1`r`n" -Encoding ASCII
  } else {
    $fakePath = Join-Path $tempDir "matlab"
    Set-Content -LiteralPath $fakePath -Value "#!/bin/sh`nexit 1`n" -Encoding ASCII
    & chmod +x $fakePath
  }
  $env:SKYBRIDGE_MATLAB_EXE = $fakePath
  $env:PATH = $tempDir + [IO.Path]::PathSeparator + $oldPath

  $failureRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command apply `
    -TaskId $failureTaskId `
    -WorkerId "smoke-matlab-worker" `
    -OutputDir $failureOutputDir `
    -Confirm `
    -ConfirmationText "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY" `
    -Json
  $failureText = ($failureRaw | Out-String).Trim()
  Assert-NoUnsafeText $failureText
  $failure = $failureText | ConvertFrom-Json
  if ($failure.ok -ne $false) { throw "Fake MATLAB apply should fail." }
  if ($failure.evidence.ok -ne $false) { throw "Failure evidence ok should be false." }
  if (@($failure.evidence.changed_files).Count -ne 0) { throw "Failure evidence should not list nonexistent changed_files." }
  if (@($failure.evidence.existing_outputs).Count -ne 0) { throw "Failure evidence should not list nonexistent existing_outputs." }
  if (@($failure.evidence.expected_outputs_missing).Count -ne 3) { throw "Failure evidence should list three missing expected outputs." }
  if ($failure.evidence.manifest_exists -ne $false) { throw "Failure evidence manifest_exists should be false." }
  if ($failure.evidence.summary_exists -ne $false) { throw "Failure evidence summary_exists should be false." }
  if ($failure.evidence.metrics_exists -ne $false) { throw "Failure evidence metrics_exists should be false." }
  Assert-False $failure.evidence.raw_stdout_included "failure evidence raw_stdout_included"
  Assert-False $failure.evidence.raw_stderr_included "failure evidence raw_stderr_included"
  Assert-False $failure.evidence.codex_run_called "failure evidence codex_run_called"
  Assert-False $failure.evidence.arbitrary_shell_enabled "failure evidence arbitrary_shell_enabled"
  Assert-False $failure.evidence.worker_loop_started "failure evidence worker_loop_started"
  Assert-TokenPrintedFalse $failure.evidence

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-success-evidence-validation"
    success_changed_files_count = @($success.evidence.changed_files).Count
    success_expected_combination_count = [int]$success.evidence.expected_combination_count
    success_manifest_exists = [bool]$success.evidence.manifest_exists
    success_summary_exists = [bool]$success.evidence.summary_exists
    success_metrics_exists = [bool]$success.evidence.metrics_exists
    failure_changed_files_count = @($failure.evidence.changed_files).Count
    failure_existing_outputs_count = @($failure.evidence.existing_outputs).Count
    failure_expected_outputs_missing_count = @($failure.evidence.expected_outputs_missing).Count
    raw_stdout_included = $false
    raw_stderr_included = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  $env:PATH = $oldPath
  if ($null -eq $oldMatlabExe) { Remove-Item Env:SKYBRIDGE_MATLAB_EXE -ErrorAction SilentlyContinue } else { $env:SKYBRIDGE_MATLAB_EXE = $oldMatlabExe }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $successFullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $failureFullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
