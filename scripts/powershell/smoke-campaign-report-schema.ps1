$ErrorActionPreference = "Stop"

$report = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
if (-not $report.ok) { throw "Expected runner-report ok." }
if ($report.token_printed -ne $false -or $report.report.token_printed -ne $false) { throw "Expected token_printed=false." }
if ($report.report.schema -ne "skybridge.campaign_run_report.v1") { throw "Unexpected report schema: $($report.report.schema)" }

$required = @(
  "schema",
  "generated_at",
  "project_id",
  "campaign_id",
  "campaign_status",
  "current_step_id",
  "current_goal_id",
  "current_goal_status",
  "current_goal_unexecuted",
  "step_ledger",
  "evidence_ledger",
  "hygiene_summary",
  "queue_control_readiness",
  "blockers",
  "warnings",
  "acceptance_summary",
  "artifact_paths",
  "token_printed"
)
foreach ($name in $required) {
  if (-not $report.report.PSObject.Properties[$name]) { throw "Report missing required section: $name" }
}
if (@($report.report.step_ledger).Count -lt 12) { throw "Expected full 12-step ledger." }
if (@($report.report.evidence_ledger.all).Count -eq 0) { throw "Expected evidence ledger entries." }

[pscustomobject]@{ ok = $true; scenario = "campaign-report-schema"; token_printed = $false } | ConvertTo-Json -Compress
