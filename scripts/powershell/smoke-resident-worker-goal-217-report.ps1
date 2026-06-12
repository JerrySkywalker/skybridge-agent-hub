$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$report = Invoke-LocalSupervisorSmokeCommand -Command "safe-report"
foreach ($path in @($report.report_json_path, $report.report_markdown_path, $report.supervisor_heartbeat_path)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "Report artifact missing: $path" }
}
Assert-FalseProperty $report "execution_enabled"
Assert-FalseProperty $report "queue_apply_enabled"
Assert-TrueProperty $report "no_codex_execution"
Assert-TrueProperty $report "no_task_claim"
[pscustomobject]@{ ok = $true; scenario = "resident-worker-goal-217-report"; token_printed = $false } | ConvertTo-Json -Compress
