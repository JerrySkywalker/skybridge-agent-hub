[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$doctorId = "fallback-fixture-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-doctor/$doctorId"
$fullOutputDir = Join-Path $RepoRoot $outputDir
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"

try {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command fixture `
    -FixtureCase fallback-success `
    -OutputDir $outputDir `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $doctor = $text | ConvertFrom-Json

  if ([string]$doctor.schema -ne "skybridge.matlab_doctor.v1") { throw "Unexpected doctor schema." }
  Assert-True $doctor.ok "fallback fixture ok"
  Assert-False $doctor.batch_supported "fallback fixture batch_supported"
  Assert-True $doctor.fallback_supported "fallback fixture fallback_supported"
  Assert-True $doctor.startup_ok "fallback fixture startup_ok"
  if ([string]$doctor.license_status -ne "available") { throw "Expected license_status=available." }
  Assert-True $doctor.output_write_ok "fallback fixture output_write_ok"
  Assert-True $doctor.minimal_compute_ok "fallback fixture minimal_compute_ok"
  Assert-False $doctor.matlab_invoked "fallback fixture matlab_invoked"
  Assert-False $doctor.raw_stdout_included "fallback fixture raw_stdout_included"
  Assert-False $doctor.raw_stderr_included "fallback fixture raw_stderr_included"
  Assert-False $doctor.codex_run_called "fallback fixture codex_run_called"
  Assert-False $doctor.arbitrary_shell_enabled "fallback fixture arbitrary_shell_enabled"
  Assert-False $doctor.worker_loop_started "fallback fixture worker_loop_started"
  Assert-TokenPrintedFalse $doctor

  foreach ($name in @("doctor_summary.json", "doctor_metrics.csv")) {
    $path = Join-Path $fullOutputDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing fallback fixture output $name." }
    Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $path)
  }

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-doctor-fallback-fixture"
    batch_supported = $false
    fallback_supported = $true
    minimal_compute_ok = $true
    output_write_ok = $true
    matlab_invoked = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $fullOutputDir -Recurse -Force -ErrorAction SilentlyContinue
}
