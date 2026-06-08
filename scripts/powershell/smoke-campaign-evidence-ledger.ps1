$ErrorActionPreference = "Stop"

$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
$ledger = $result.report.evidence_ledger
if (-not $ledger) { throw "Missing evidence_ledger." }
foreach ($section in @("all", "task", "pr", "ci", "finalizer", "gate", "missing", "recovered", "not_applicable")) {
  if (-not $ledger.PSObject.Properties[$section]) { throw "Evidence ledger missing section: $section" }
}
if (@($ledger.all | Where-Object { $_.goal_id -eq "super-190-campaign-run-report-evidence-ledger" -and $_.classification -in @("present_evidence", "recovered_evidence") }).Count -lt 1) {
  throw "Expected present or recovered evidence for completed Goal 190."
}
$currentGoal = [string]$result.report.current_goal_id
if (@($ledger.missing | Where-Object { $_.goal_id -eq $currentGoal }).Count -lt 1) {
  throw "Expected explicit missing evidence for current goal $currentGoal."
}
if (@($ledger.recovered | Where-Object { $_.goal_id -eq "super-189-ci-guardian-pr-finalizer-hardening" }).Count -lt 1) {
  throw "Expected recovered evidence for Goal 189."
}
if ($result.report.token_printed -ne $false) { throw "Expected token_printed=false." }

[pscustomobject]@{ ok = $true; scenario = "campaign-evidence-ledger"; token_printed = $false } | ConvertTo-Json -Compress
