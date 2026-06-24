[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$doctorId = "smoke-matlab-doctor-fixture-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-doctor/$doctorId"
$fullOutputDir = Join-Path $RepoRoot $outputDir
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"

try {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command fixture `
    -OutputDir $outputDir `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $fixture = $text | ConvertFrom-Json

  if ([string]$fixture.schema -ne "skybridge.matlab_doctor.v1") { throw "Unexpected doctor fixture schema." }
  if ($fixture.ok -ne $true) { throw "Doctor fixture should pass." }
  if ([string]$fixture.mode -ne "fixture") { throw "Fixture mode mismatch." }
  Assert-False $fixture.matlab_invoked "doctor fixture matlab_invoked"
  Assert-False $fixture.raw_stdout_included "doctor fixture raw_stdout_included"
  Assert-False $fixture.raw_stderr_included "doctor fixture raw_stderr_included"
  Assert-False $fixture.codex_run_called "doctor fixture codex_run_called"
  Assert-False $fixture.arbitrary_shell_enabled "doctor fixture arbitrary_shell_enabled"
  Assert-False $fixture.worker_loop_started "doctor fixture worker_loop_started"
  Assert-TokenPrintedFalse $fixture

  foreach ($name in @("doctor_summary.json", "doctor_metrics.csv")) {
    $path = Join-Path $fullOutputDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing doctor fixture output $name." }
    Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $path)
  }

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-doctor-fixture"
    output_dir = $fixture.output_dir
    output_write_ok = [bool]$fixture.output_write_ok
    minimal_compute_ok = [bool]$fixture.minimal_compute_ok
    matlab_invoked = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  if (Test-Path -LiteralPath $fullOutputDir) {
    Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}
