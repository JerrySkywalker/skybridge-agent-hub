[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$taskId = "smoke-matlab-failed-evidence-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-golden-trial/$taskId"
$fullOutputDir = Join-Path $RepoRoot $outputDir
$runnerScript = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-fake-matlab-" + [Guid]::NewGuid().ToString("n"))
$oldPath = $env:PATH
$oldMatlabExe = $env:SKYBRIDGE_MATLAB_EXE

try {
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

  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript `
    -Command apply `
    -TaskId $taskId `
    -WorkerId "smoke-matlab-worker" `
    -OutputDir $outputDir `
    -Confirm `
    -ConfirmationText "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json

  if ($result.ok -ne $false) { throw "Fake MATLAB apply should fail." }
  if (-not $result.evidence) { throw "Failed runner should return evidence." }
  if ($result.evidence.ok -ne $false) { throw "Failed evidence ok should be false." }
  if ([string]::IsNullOrWhiteSpace([string]$result.evidence.failure_category)) { throw "Failed evidence should include failure_category." }
  if (@($result.evidence.changed_files).Count -ne 0) { throw "Failed evidence should not list nonexistent changed_files." }
  if (@($result.evidence.existing_outputs).Count -ne 0) { throw "Failed evidence should not list nonexistent existing_outputs." }
  if (@($result.evidence.expected_outputs_missing).Count -ne 3) { throw "Failed evidence should list the three missing expected outputs." }
  Assert-False $result.evidence.raw_stdout_included "failed evidence raw_stdout_included"
  Assert-False $result.evidence.raw_stderr_included "failed evidence raw_stderr_included"
  Assert-False $result.evidence.codex_run_called "failed evidence codex_run_called"
  Assert-False $result.evidence.arbitrary_shell_enabled "failed evidence arbitrary_shell_enabled"
  Assert-False $result.evidence.worker_loop_started "failed evidence worker_loop_started"
  Assert-TokenPrintedFalse $result.evidence

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-failed-evidence-accuracy"
    failure_category = [string]$result.evidence.failure_category
    changed_files_count = @($result.evidence.changed_files).Count
    existing_outputs_count = @($result.evidence.existing_outputs).Count
    expected_outputs_missing_count = @($result.evidence.expected_outputs_missing).Count
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
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
