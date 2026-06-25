$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc1-handoff.ps1") -Command status -WriteReport -Json
if ($LASTEXITCODE -ne 0) { throw "RC1 handoff report command failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc1_handoff.v1") { throw "Unexpected RC1 handoff schema." }
Assert-FileExists $result.report_json_path
Assert-FileExists $result.report_markdown_path
$jsonText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_json_path)
$markdownText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_markdown_path)
Assert-NoUnsafeText $jsonText
Assert-NoUnsafeText $markdownText
Assert-False $result.github_release_created "github_release_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-rc1-handoff-report"
  report_json_path = [string]$result.report_json_path
  report_markdown_path = [string]$result.report_markdown_path
  token_printed = $false
} | ConvertTo-Json
