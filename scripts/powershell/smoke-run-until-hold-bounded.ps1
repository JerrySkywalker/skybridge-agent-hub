[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\run-until-hold-bounded-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function New-Task {
  param(
    [string]$TaskId,
    [string]$Status = "queued",
    [string]$Risk = "low",
    [string]$TaskType = "docs",
    [string[]]$AllowedPaths
  )
  if (-not $AllowedPaths -and $TaskId -match "^run-until-hold-pilot-docs-(00[1-3])$") {
    $AllowedPaths = @("docs/operations/RUN_UNTIL_HOLD_PILOT_$($Matches[1]).md")
  }
  [pscustomobject]@{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = "Fixture task $TaskId"
    body = "Fixture body."
    status = $Status
    risk = $Risk
    task_type = $TaskType
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($AllowedPaths)
    hygiene_metadata = [pscustomobject]@{ bounded_loop_pilot = ($TaskId -like "run-until-hold-pilot-docs-*"); allowed_worker_id = "jerry-win-local-01" }
    token_printed = $false
  }
}

function New-Hygiene {
  [pscustomobject]@{
    schema = "skybridge.task_hygiene_report.v1"
    ok = $true
    unsafe_to_requeue_candidates = @([pscustomobject]@{ task_id = "old-failed-001"; classification = "unsafe-to-requeue" })
    archive_or_keep_blocked_candidates = @([pscustomobject]@{ task_id = "old-blocked-001"; classification = "historical-residue" })
    task_classifications = @()
    token_printed = $false
  }
}

function Invoke-Bounded {
  param([string]$Name, [object[]]$Tasks, [string[]]$Extra = @(), [object[]]$Workers)
  if (-not $Workers) { $Workers = @([pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "online"; enabled = $true; capabilities = @("codex", "docs", "windows"); token_printed = $false }) }
  $tasksPath = Write-Fixture "$Name-tasks.json" ([pscustomobject]@{ tasks = @($Tasks) })
  $workersPath = Write-Fixture "$Name-workers.json" ([pscustomobject]@{ workers = @($Workers) })
  $hygienePath = Write-Fixture "$Name-hygiene.json" (New-Hygiene)
  $gatePath = Write-Fixture "$Name-second-gate.json" ([pscustomobject]@{ project_control_state = "paused"; allowed_preview_only = $true; allowed_execution = $false; token_printed = $false })
  $stateDir = Join-Path $tmpRoot "$Name-state"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-run-until-hold-bounded.ps1 `
    -FixtureTasksFile $tasksPath `
    -FixtureWorkersFile $workersPath `
    -FixtureHygieneFile $hygienePath `
    -FixtureSecondGateFile $gatePath `
    -FixtureStateDir $stateDir `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "bounded script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.run_until_hold_bounded.v1") { throw "Unexpected bounded schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  Assert-False $result.project_control.project_control_unpaused "$Name project_control_unpaused"
  Assert-False $result.forbidden_actions.recursive_run_until_hold "$Name recursive_run_until_hold"
  Assert-False $result.forbidden_actions.old_task_claimed "$Name old_task_claimed"
  Assert-False $result.forbidden_actions.old_task_requeued "$Name old_task_requeued"
  return $result
}

function Assert-Stop {
  param($Result, [string]$StopReason)
  if ([string]$Result.stop_reason -ne $StopReason) { throw "Expected stop_reason $StopReason but got $($Result.stop_reason)." }
}

$pilot1 = New-Task -TaskId "run-until-hold-pilot-docs-001"
$pilot2 = New-Task -TaskId "run-until-hold-pilot-docs-002"
$pilot3 = New-Task -TaskId "run-until-hold-pilot-docs-003"
$oldFailed = New-Task -TaskId "old-failed-001" -Status "failed"
$oldBlocked = New-Task -TaskId "old-blocked-001" -Status "blocked"
$oldCompleted = New-Task -TaskId "old-completed-001" -Status "completed"
$activeNonPilot = New-Task -TaskId "active-non-pilot-001"

$preview = Invoke-Bounded -Name "preview" -Tasks @($oldFailed, $oldBlocked, $oldCompleted, $activeNonPilot, $pilot1, $pilot2, $pilot3) -Extra @("-Preview", "-MaxTasks", "2")
if (@($preview.selected_candidates).Count -ne 2) { throw "Preview should select at most MaxTasks=2." }
Assert-False $preview.executed_task_count "preview executed count"
Assert-Stop $preview "preview_ready"
Assert-True $preview.old_residue_exclusion.no_old_task_claimed "preview old task not claimed"
Assert-True $preview.old_residue_exclusion.no_old_task_requeued "preview old task not requeued"

$apply = Invoke-Bounded -Name "apply-success" -Tasks @($pilot1, $pilot2, $pilot3) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-MaxTasks", "2", "-FixtureCodexSuccess")
Assert-True $apply.ok "apply success ok"
if ($apply.executed_task_count -ne 2) { throw "Apply should execute exactly 2 tasks." }
if ($apply.codex_execution_count -ne 2) { throw "Apply should call Codex at most once per executed task." }
Assert-Stop $apply "completed_max_tasks"
Assert-True $apply.evidence_summary.evidence_present "apply evidence present"

$missingConfirm = Invoke-Bounded -Name "missing-confirm" -Tasks @($pilot1) -Extra @("-Apply")
Assert-False $missingConfirm.ok "missing confirm ok"
Assert-Stop $missingConfirm "operator_review_required"

$failure = Invoke-Bounded -Name "first-failure" -Tasks @($pilot1, $pilot2) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-FixtureCodexFailure")
Assert-False $failure.ok "failure ok"
if ($failure.executed_task_count -ne 1) { throw "Stop-on-first-failure should execute one task." }
Assert-Stop $failure "task_failed_with_evidence"

$noSafe = Invoke-Bounded -Name "no-safe" -Tasks @() -Extra @("-Preview")
Assert-Stop $noSafe "no_safe_candidate"

foreach ($case in @(
  @{ name = "old-failed"; task = $oldFailed },
  @{ name = "old-blocked"; task = $oldBlocked },
  @{ name = "old-completed"; task = $oldCompleted },
  @{ name = "active-non-pilot"; task = $activeNonPilot },
  @{ name = "unsafe-path"; task = (New-Task -TaskId "run-until-hold-pilot-docs-001" -AllowedPaths @("scripts/powershell/deploy.ps1")) }
)) {
  $result = Invoke-Bounded -Name $case.name -Tasks @($case.task) -Extra @("-Preview")
  if (@($result.selected_candidates).Count -ne 0) { throw "$($case.name) selected unexpectedly." }
}

$duplicate = Invoke-Bounded -Name "duplicate-candidates" -Tasks @($pilot1, $pilot1, $pilot2) -Extra @("-Preview", "-MaxTasks", "2")
if (@($duplicate.selected_candidates).Count -gt 2) { throw "Duplicate candidate case exceeded MaxTasks." }

$codexUnavailable = Invoke-Bounded -Name "codex-unavailable" -Tasks @($pilot1, $pilot2) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-FixtureCodexUnavailable")
Assert-Stop $codexUnavailable "task_failed_with_evidence"
if ($codexUnavailable.codex_execution_count -ne 0) { throw "Codex unavailable should not count an execution." }

$unsafeChange = Invoke-Bounded -Name "unsafe-change" -Tasks @($pilot1) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-FixtureCodexUnsafePath")
Assert-Stop $unsafeChange "unsafe_path_changed"

$evidenceMissing = Invoke-Bounded -Name "evidence-missing" -Tasks @($pilot1) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-FixtureCodexSuccess", "-FixtureEvidenceMissing")
Assert-Stop $evidenceMissing "evidence_missing"
Assert-False $evidenceMissing.evidence_summary.evidence_present "evidence missing present"

$validationFailure = Invoke-Bounded -Name "validation-failure" -Tasks @($pilot1) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS", "-FixtureValidationFailure")
Assert-Stop $validationFailure "validation_failed"

$workerOffline = Invoke-Bounded -Name "worker-offline" -Tasks @($pilot1) -Workers @([pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "offline"; enabled = $true; capabilities = @("codex", "docs", "windows") }) -Extra @("-Preview")
Assert-Stop $workerOffline "no_safe_candidate"
if (@($workerOffline.skipped_tasks.reasons) -notcontains "worker_offline") { throw "worker_offline rejection missing." }

$stale = New-Task -TaskId "run-until-hold-pilot-docs-001"
$stale | Add-Member -NotePropertyName lease -NotePropertyValue ([pscustomobject]@{ lease_id = "fixture-lease"; expires_at = (Get-Date).ToUniversalTime().AddMinutes(-10).ToString("o") }) -Force
$staleResult = Invoke-Bounded -Name "stale-claim" -Tasks @($stale) -Extra @("-Preview")
Assert-Stop $staleResult "no_safe_candidate"
if (@($staleResult.skipped_tasks.reasons) -notcontains "stale_claim_or_lease") { throw "stale claim rejection missing." }

$runtime = Invoke-Bounded -Name "max-runtime" -Tasks @($pilot1) -Extra @("-Preview", "-FixtureMaxRuntimeExceeded")
Assert-Stop $runtime "max_runtime_exceeded"

$reportPath = Write-Fixture "bounded-report-source.json" $apply
$reportRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-until-hold-report.ps1 -FixtureBoundedRunFile $reportPath -Json
if ($LASTEXITCODE -ne 0) { throw "run-until-hold report failed." }
$reportText = (($reportRaw | Out-String).Trim())
Assert-NoUnsafeText $reportText
$report = $reportText | ConvertFrom-Json
if ($report.schema -ne "skybridge.run_until_hold_report.v1") { throw "Unexpected report schema." }
Assert-True $report.project_control_stayed_paused "report project control paused"
Assert-True $report.run_until_hold_stayed_bounded "report bounded"
Assert-False $report.token_printed "report token_printed"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "run-until-hold-bounded"
  scenarios = @(
    "preview_selects_at_most_MaxTasks",
    "apply_executes_at_most_MaxTasks",
    "stops_on_first_failure",
    "stops_on_no_safe_candidate",
    "rejects_old_failed_tasks",
    "rejects_old_blocked_tasks",
    "rejects_completed_old_tasks",
    "rejects_unsafe_allowed_paths",
    "rejects_active_non_pilot_task",
    "rejects_duplicate_candidates_by_max_limit",
    "handles_codex_unavailable",
    "handles_codex_unsafe_path_change",
    "handles_evidence_missing",
    "handles_validation_failure",
    "handles_worker_offline",
    "handles_stale_claim_or_lease",
    "max_runtime_exceeded",
    "no_recursion",
    "project_control_remains_paused",
    "token_printed_false"
  )
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "run-until-hold-bounded" }
