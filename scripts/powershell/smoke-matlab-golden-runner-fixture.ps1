[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$taskId = "smoke-matlab-golden-fixture-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-golden-trial/$taskId"
$fullOutputDir = Join-Path $RepoRoot $outputDir
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"

try {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command fixture `
    -TaskId $taskId `
    -WorkerId "smoke-matlab-worker" `
    -OutputDir $outputDir `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $fixture = $text | ConvertFrom-Json

  if ($fixture.ok -ne $true) { throw "Fixture runner failed: $($fixture.blockers -join ';')" }
  if ([string]$fixture.mode -ne "fixture") { throw "Fixture mode mismatch." }
  if ([int]$fixture.combination_count -ne 2) { throw "Expected fixture combination_count=2." }
  if ([int]$fixture.completed_count -ne 2) { throw "Expected completed_count=2." }
  if ([int]$fixture.failed_count -ne 0) { throw "Expected failed_count=0." }
  Assert-False $fixture.matlab_invoked "fixture matlab_invoked"
  Assert-False $fixture.raw_stdout_included "fixture raw_stdout_included"
  Assert-False $fixture.raw_stderr_included "fixture raw_stderr_included"
  Assert-False $fixture.raw_mat_files_uploaded "fixture raw_mat_files_uploaded"
  Assert-False $fixture.codex_run_called "fixture codex_run_called"
  Assert-False $fixture.arbitrary_shell_enabled "fixture arbitrary_shell_enabled"
  Assert-False $fixture.worker_loop_started "fixture worker_loop_started"
  Assert-TokenPrintedFalse $fixture

  foreach ($name in @("manifest.json", "summary.json", "metrics.csv")) {
    $path = Join-Path $fullOutputDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing fixture output $name." }
    if ($name -ne "metrics.csv") { Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $path) }
  }

  $validateRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command validate-output `
    -TaskId $taskId `
    -WorkerId "smoke-matlab-worker" `
    -OutputDir $outputDir `
    -Json
  $validateText = ($validateRaw | Out-String).Trim()
  Assert-NoUnsafeText $validateText
  $validate = $validateText | ConvertFrom-Json
  if ($validate.ok -ne $true) { throw "Fixture output validation failed: $($validate.blockers -join ';')" }

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-golden-runner-fixture"
    task_id = $taskId
    manifest_path = $fixture.manifest_path
    summary_path = $fixture.summary_path
    metrics_path = $fixture.metrics_path
    completed_count = $fixture.completed_count
    failed_count = $fixture.failed_count
    matlab_invoked = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    raw_mat_files_uploaded = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  if (Test-Path -LiteralPath $fullOutputDir) {
    Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
