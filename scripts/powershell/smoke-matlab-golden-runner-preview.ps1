[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$taskId = "smoke-matlab-golden-preview-" + [Guid]::NewGuid().ToString("n")
$outputDir = ".agent/tmp/matlab-golden-trial/$taskId"
$scriptPath = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
  -Command preview `
  -TaskId $taskId `
  -WorkerId "smoke-matlab-worker" `
  -OutputDir $outputDir `
  -Json
$text = ($raw | Out-String).Trim()
Assert-NoUnsafeText $text
$preview = $text | ConvertFrom-Json

if ([string]$preview.schema -ne "skybridge.matlab_parameter_sweep_runner.v1") { throw "Unexpected runner preview schema." }
if ($preview.ok -ne $true) { throw "Runner preview should be ok for default tiny grid: $($preview.blockers -join ';')" }
if ([string]$preview.mode -ne "preview") { throw "Preview mode mismatch." }
if ([int]$preview.combination_count -ne 2) { throw "Expected combination_count=2." }
Assert-False $preview.matlab_invoked "preview matlab_invoked"
Assert-False $preview.raw_stdout_included "preview raw_stdout_included"
Assert-False $preview.raw_stderr_included "preview raw_stderr_included"
Assert-False $preview.raw_mat_files_uploaded "preview raw_mat_files_uploaded"
Assert-False $preview.codex_run_called "preview codex_run_called"
Assert-False $preview.arbitrary_shell_enabled "preview arbitrary_shell_enabled"
Assert-False $preview.worker_loop_started "preview worker_loop_started"
Assert-TokenPrintedFalse $preview

$fullOutputDir = Join-Path $RepoRoot $outputDir
if (Test-Path -LiteralPath $fullOutputDir) { throw "Preview should not create output directory." }

[pscustomobject]@{
  ok = $true
  smoke = "matlab-golden-runner-preview"
  schema = $preview.schema
  combination_count = $preview.combination_count
  matlab_available = [bool]$preview.matlab_available
  matlab_invoked = $false
  raw_stdout_included = $false
  raw_stderr_included = $false
  raw_mat_files_uploaded = $false
  codex_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
