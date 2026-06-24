[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$doctorId = "smoke-matlab-doctor-preview-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-doctor/$doctorId"
$fullOutputDir = Join-Path $RepoRoot $outputDir
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-doctor.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
  -Command preview `
  -OutputDir $outputDir `
  -Json
$text = ($raw | Out-String).Trim()
Assert-NoUnsafeText $text
$preview = $text | ConvertFrom-Json

if ([string]$preview.schema -ne "skybridge.matlab_doctor.v1") { throw "Unexpected doctor preview schema." }
if ([string]$preview.mode -ne "preview") { throw "Preview mode mismatch." }
Assert-False $preview.matlab_invoked "doctor preview matlab_invoked"
Assert-False $preview.claim_created "doctor preview claim_created"
Assert-False $preview.execution_started "doctor preview execution_started"
Assert-False $preview.raw_stdout_included "doctor preview raw_stdout_included"
Assert-False $preview.raw_stderr_included "doctor preview raw_stderr_included"
Assert-False $preview.codex_run_called "doctor preview codex_run_called"
Assert-False $preview.arbitrary_shell_enabled "doctor preview arbitrary_shell_enabled"
Assert-False $preview.worker_loop_started "doctor preview worker_loop_started"
Assert-TokenPrintedFalse $preview

if (Test-Path -LiteralPath $fullOutputDir) { throw "Doctor preview should not create output directory." }

[pscustomobject]@{
  ok = $true
  smoke = "matlab-doctor-preview"
  schema = $preview.schema
  matlab_detected = [bool]$preview.matlab_detected
  failure_category = [string]$preview.failure_category
  matlab_invoked = $false
  raw_stdout_included = $false
  raw_stderr_included = $false
  codex_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
