[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\start-one-hold-report-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Invoke-HoldReport {
  param($Name, $Task, $Apply, $Evidence = $null, [switch]$AllowUnsafeFlags)
  $taskPath = Write-Fixture "$Name-task.json" ([pscustomobject]@{ task = $Task })
  $applyPath = Write-Fixture "$Name-apply.json" $Apply
  $args = @(
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", ".\scripts\powershell\skybridge-start-one-hold-report.ps1",
    "-FixtureTaskFile", $taskPath,
    "-FixtureStartOneApplyPilotFile", $applyPath,
    "-Json"
  )
  if ($Evidence) {
    $evidencePath = Write-Fixture "$Name-evidence.json" $Evidence
    $args += @("-FixtureEvidenceFile", $evidencePath)
  }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "hold report failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.start_one_hold_report.v1") { throw "Unexpected hold report schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  if (-not $AllowUnsafeFlags) {
    Assert-False $result.project_control_unpaused "$Name project_control_unpaused"
    Assert-False $result.run_until_hold_called "$Name run_until_hold_called"
    Assert-False $result.old_residue_selected "$Name old_residue_selected"
  }
  return $result
}

$baseApply = [pscustomobject]@{
  schema = "skybridge.start_one_apply_pilot.v1"
  ok = $true
  status = "terminal_completed"
  terminal_state = "already_completed_noop"
  hold_reason = "pilot_task_already_completed"
  failure_category = $null
  evidence_summary = [pscustomobject]@{
    evidence_present = $true
    schema = "skybridge.start_one_apply_pilot_evidence.v2"
    files_changed = @("docs/operations/START_ONE_APPLY_PILOT.md")
    prompt_content_included = $false
    log_content_included = $false
    credential_values_included = $false
    token_printed = $false
  }
  old_residue_exclusion = [pscustomobject]@{ no_old_residue_eligible = $true }
  project_control = [pscustomobject]@{ project_control_unpaused = $false }
  forbidden_actions = [pscustomobject]@{ run_until_hold_called = $false }
  manual_operator_review_needed = $false
  token_printed = $false
}

$completedTask = [pscustomobject]@{ task_id = "start-one-apply-pilot-docs-001"; status = "completed"; token_printed = $false }
$completed = Invoke-HoldReport -Name "completed" -Task $completedTask -Apply $baseApply
Assert-True $completed.ok "completed ok"
if ($completed.terminal_state -ne "already_completed_noop") { throw "Expected already_completed_noop." }
Assert-True $completed.evidence_present "completed evidence present"

$failedApply = $baseApply.PSObject.Copy()
$failedApply.ok = $false
$failedApply.status = "failed_with_evidence"
$failedApply.terminal_state = "validation_failed"
$failedApply.hold_reason = "validation_failed"
$failedApply | Add-Member -NotePropertyName failure_category -NotePropertyValue "validation_failed" -Force
$failedApply.manual_operator_review_needed = $true
$failedApply.evidence_summary | Add-Member -NotePropertyName failure_category -NotePropertyValue "validation_failed" -Force
$failedTask = [pscustomobject]@{ task_id = "start-one-apply-pilot-docs-001"; status = "failed"; token_printed = $false }
$failed = Invoke-HoldReport -Name "failed-with-evidence" -Task $failedTask -Apply $failedApply
Assert-True $failed.ok "failed hold ok"
if ($failed.terminal_state -ne "validation_failed") { throw "Expected validation_failed." }
if ($failed.hold_reason -ne "validation_failed") { throw "Expected hold reason validation_failed." }
Assert-True $failed.manual_operator_review_needed "failed manual review"

$unsafeApply = $failedApply.PSObject.Copy()
$unsafeApply.project_control = [pscustomobject]@{ project_control_unpaused = $true }
$unsafe = Invoke-HoldReport -Name "unsafe-flag" -Task $failedTask -Apply $unsafeApply -AllowUnsafeFlags
Assert-False $unsafe.ok "unsafe flag ok"
if ($unsafe.recommended_next_safe_action -notmatch "FAILED_CLOSED") { throw "Expected FAILED_CLOSED recommendation." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "start-one-hold-report"
  scenarios = @("completed_terminal", "failed_with_evidence_hold", "unsafe_flag_failed_closed")
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "start-one-hold-report"
}
