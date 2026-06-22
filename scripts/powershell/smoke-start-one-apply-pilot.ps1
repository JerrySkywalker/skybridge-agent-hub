[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\start-one-apply-pilot-smoke"
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
    [string[]]$AllowedPaths = @("docs/operations/START_ONE_APPLY_PILOT.md"),
    [string[]]$BlockedPaths = @(".env", "secrets/**", "deploy/**")
  )
  [pscustomobject]@{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = "Fixture task $TaskId"
    body = "Fixture body."
    status = $Status
    risk = $Risk
    task_type = $TaskType
    source = "manual"
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    hygiene_metadata = [pscustomobject]@{ safe_start_one_pilot = ($TaskId -eq "start-one-apply-pilot-docs-001") }
    token_printed = $false
  }
}

function New-Hygiene {
  param([switch]$IncludePilot)
  $unsafeTasks = 1..12 | ForEach-Object { "unsafe-to-requeue-$($_)" }
  $blockedTasks = @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001")
  [pscustomobject]@{
    schema = "skybridge.task_hygiene_report.v1"
    ok = $true
    unsafe_to_requeue_candidates = @($unsafeTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "unsafe-to-requeue" } })
    archive_or_keep_blocked_candidates = @($blockedTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "historical-residue" } })
    task_classifications = @(
      if ($IncludePilot) {
        [pscustomobject]@{
          task_id = "start-one-apply-pilot-docs-001"
          status = "queued"
          hygiene_status = "active_ok"
          classification = "not-residue"
          risk = "not_reported"
          task_type = "docs"
          assigned_worker_id = "-"
          recommended_action = "No Goal 315 action."
        }
      }
    )
    token_printed = $false
  }
}

function Invoke-ApplyPilot {
  param([string]$Name, [object[]]$Tasks, [string[]]$Extra = @(), [object[]]$Workers = @($script:Worker), [switch]$IncludePilotHygiene)
  $tasksPath = Write-Fixture "$Name-tasks.json" ([pscustomobject]@{ tasks = @($Tasks) })
  $workersPath = Write-Fixture "$Name-workers.json" ([pscustomobject]@{ workers = @($Workers) })
  $hygienePath = Write-Fixture "$Name-hygiene.json" (New-Hygiene -IncludePilot:$IncludePilotHygiene)
  $gatePath = Write-Fixture "$Name-second-gate.json" $script:SecondGate
  $stateDir = Join-Path $tmpRoot "$Name-state"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-start-one-apply-pilot.ps1 `
    -FixtureTasksFile $tasksPath `
    -FixtureWorkersFile $workersPath `
    -FixtureHygieneFile $hygienePath `
    -FixtureSecondGateFile $gatePath `
    -FixtureStateDir $stateDir `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "apply pilot script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.start_one_apply_pilot.v1") { throw "Unexpected apply schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  Assert-False $result.forbidden_actions.run_until_hold_called "$Name run_until_hold_called"
  Assert-False $result.forbidden_actions.project_control_unpaused "$Name project_control_unpaused"
  return $result
}

function Invoke-SeedFixture {
  param([string]$Name)
  $tasksPath = Write-Fixture "$Name-seed-empty-tasks.json" ([pscustomobject]@{ tasks = @() })
  $stateDir = Join-Path $tmpRoot "$Name-seed-state"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-seed-start-one-pilot-task.ps1 `
    -FixtureTasksFile $tasksPath `
    -FixtureStateDir $stateDir `
    -Apply `
    -Confirm I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "seed fixture failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $seed = $text | ConvertFrom-Json
  Assert-True $seed.ok "$Name seed ok"
  $seededPath = Join-Path $stateDir "seeded-task.json"
  if (-not (Test-Path -LiteralPath $seededPath -PathType Leaf)) { throw "Seed fixture did not write seeded-task.json." }
  return $seededPath
}

$script:Worker = [pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "online"; enabled = $true; capabilities = @("codex", "docs", "windows"); token_printed = $false }
$script:HeartbeatOnlyWorker = [pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "online"; enabled = $true; capabilities = @("heartbeat"); token_printed = $false }
$script:SecondGate = [pscustomobject]@{
  schema = "skybridge.execution_second_gate_readiness.v1"
  ok = $true
  status = "preview_ready"
  allowed_preview_only = $true
  allowed_execution = $false
  project_control_state = "paused"
  token_printed = $false
}

$pilot = New-Task -TaskId "start-one-apply-pilot-docs-001"
$oldFailed = 1..12 | ForEach-Object { New-Task -TaskId "unsafe-to-requeue-$($_)" -Status "failed" }
$oldBlocked = @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001") | ForEach-Object { New-Task -TaskId $_ -Status "blocked" }
$remoteFailed = New-Task -TaskId "remote-docs-exec-pilot-001" -Status "failed"
$completed = New-Task -TaskId "completed-residue-317" -Status "completed"

$preview = Invoke-ApplyPilot -Name "preview" -Tasks (@($oldFailed) + @($oldBlocked) + @($remoteFailed) + @($completed) + @($pilot)) -Extra @("-Preview")
if ($preview.mode -ne "preview") { throw "Expected preview mode." }
if ($preview.selected_task_id -ne "start-one-apply-pilot-docs-001") { throw "Preview did not select pilot task." }
Assert-True $preview.pilot_task_lookup.found_by_id "preview found_by_id"
Assert-True $preview.pilot_task_lookup.found_in_task_list "preview found_in_task_list"
Assert-True $preview.pilot_task_lookup.worker_match "preview worker_match"
Assert-False $preview.claim_result.claimed "preview claimed"
Assert-False $preview.would_claim "preview would_claim"
Assert-False $preview.would_run_codex "preview would_run_codex"
Assert-False $preview.would_unpause_project_control "preview would_unpause_project_control"
if ($preview.execution_result.codex_execution_count -ne 0) { throw "Preview ran Codex." }
if ($preview.old_residue_exclusion.unsafe_to_requeue_tasks_excluded -ne 12) { throw "Expected 12 unsafe exclusions." }
if ($preview.old_residue_exclusion.blocked_historical_tasks_excluded -ne 3) { throw "Expected 3 blocked exclusions." }
Assert-True $preview.old_residue_exclusion.remote_docs_exec_pilot_001_excluded "remote docs excluded"
Assert-True $preview.old_residue_exclusion.no_old_residue_eligible "old residue eligible"

$seededTaskPath = Invoke-SeedFixture -Name "seeded-pilot"
$seededPreviewRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-start-one-apply-pilot.ps1 `
  -FixtureTasksFile $seededTaskPath `
  -FixtureWorkersFile (Write-Fixture "seeded-pilot-workers.json" ([pscustomobject]@{ workers = @($script:Worker) })) `
  -FixtureHygieneFile (Write-Fixture "seeded-pilot-hygiene.json" (New-Hygiene)) `
  -FixtureSecondGateFile (Write-Fixture "seeded-pilot-second-gate.json" $script:SecondGate) `
  -FixtureStateDir (Join-Path $tmpRoot "seeded-pilot-apply-state") `
  -Preview `
  -Json
if ($LASTEXITCODE -ne 0) { throw "apply preview failed for seeded pilot task." }
$seededPreviewText = (($seededPreviewRaw | Out-String).Trim())
Assert-NoUnsafeText $seededPreviewText
$seededPreview = $seededPreviewText | ConvertFrom-Json
if ($seededPreview.selected_task_id -ne "start-one-apply-pilot-docs-001") { throw "Seeded pilot task was not accepted by apply preview." }
Assert-False $seededPreview.would_claim "seeded preview would_claim"
Assert-False $seededPreview.would_run_codex "seeded preview would_run_codex"
Assert-False $seededPreview.would_unpause_project_control "seeded preview would_unpause"

$missingRiskPilot = New-Task -TaskId "start-one-apply-pilot-docs-001" -Risk ""
$riskFallback = Invoke-ApplyPilot -Name "risk-hygiene-proof" -Tasks @($missingRiskPilot) -Extra @("-Preview") -IncludePilotHygiene
if ($riskFallback.selected_task_id -ne "start-one-apply-pilot-docs-001") { throw "Hygiene safe marker did not allow missing-risk pilot." }
Assert-True $riskFallback.pilot_task_lookup.found_in_hygiene "risk fallback found hygiene"

$blockedPathsSafe = Invoke-ApplyPilot -Name "blocked-paths-safe" -Tasks @((New-Task -TaskId "start-one-apply-pilot-docs-001" -BlockedPaths @("deploy/**", ".env", "secrets/**", ".github/settings/**"))) -Extra @("-Preview")
if ($blockedPathsSafe.selected_task_id -ne "start-one-apply-pilot-docs-001") { throw "Blocked-path guardrails poisoned safe candidate." }

$heartbeatOnlyWorker = Invoke-ApplyPilot -Name "heartbeat-only-worker" -Tasks @($pilot) -Workers @($script:HeartbeatOnlyWorker) -Extra @("-Preview")
if ($heartbeatOnlyWorker.selected_task_id -ne "start-one-apply-pilot-docs-001") { throw "Heartbeat-only worker compatibility proof did not accept the safe docs pilot." }
Assert-True $heartbeatOnlyWorker.pilot_task_lookup.worker_match "heartbeat-only worker explicit proof"

$heartbeatOnlyWithoutProofTask = New-Task -TaskId "start-one-apply-pilot-docs-001"
$heartbeatOnlyWithoutProofTask.required_capabilities = @("codex", "docs")
$heartbeatOnlyWithoutProof = Invoke-ApplyPilot -Name "heartbeat-only-without-proof" -Tasks @($heartbeatOnlyWithoutProofTask) -Workers @($script:HeartbeatOnlyWorker) -Extra @("-Preview")
if ($heartbeatOnlyWithoutProof.selected_task_id) { throw "Heartbeat-only worker without explicit compatibility proof was selected." }

$missingConfirm = Invoke-ApplyPilot -Name "missing-confirm" -Tasks @($pilot) -Extra @("-Apply")
Assert-False $missingConfirm.ok "apply requires confirmation"
if (@($missingConfirm.blockers) -notcontains "confirmation_required") { throw "Expected confirmation_required." }

$apply = Invoke-ApplyPilot -Name "apply-success" -Tasks @($pilot) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_START_ONE_SINGLE_SAFE_TASK_ONLY", "-FixtureCodexSuccess")
Assert-True $apply.claim_result.claimed "apply claimed"
Assert-True $apply.claim_result.heartbeat_refreshed_before_claim "apply refreshed heartbeat before claim"
if ($apply.execution_result.codex_execution_count -ne 1) { throw "Apply must run Codex exactly once." }
if ($apply.final_task_status -ne "completed") { throw "Expected completed final status." }
Assert-True $apply.evidence_result.ok "evidence ok"

$failedOld = Invoke-ApplyPilot -Name "old-failed-only" -Tasks @($oldFailed[0]) -Extra @("-Preview")
if ($failedOld.selected_task_id) { throw "Old failed task selected." }

$blockedOld = Invoke-ApplyPilot -Name "old-blocked-only" -Tasks @($oldBlocked[0]) -Extra @("-Preview")
if ($blockedOld.selected_task_id) { throw "Old blocked task selected." }

$completedOld = Invoke-ApplyPilot -Name "completed-only" -Tasks @($completed) -Extra @("-Preview")
if ($completedOld.selected_task_id) { throw "Completed task selected." }

$multiple = Invoke-ApplyPilot -Name "multiple-pilot" -Tasks @($pilot, $pilot) -Extra @("-Preview")
if (@($multiple.blockers) -notcontains "multiple_candidates_selected") { throw "Multiple candidates were not rejected." }

$unsafePath = Invoke-ApplyPilot -Name "unsafe-path" -Tasks @((New-Task -TaskId "start-one-apply-pilot-docs-001" -AllowedPaths @("scripts/powershell/deploy.ps1"))) -Extra @("-Preview")
if ($unsafePath.selected_task_id) { throw "Unsafe path selected." }

$deployTask = Invoke-ApplyPilot -Name "deploy-task" -Tasks @((New-Task -TaskId "start-one-apply-pilot-docs-001" -TaskType "deploy" -AllowedPaths @("docs/operations/START_ONE_APPLY_PILOT.md"))) -Extra @("-Preview")
if ($deployTask.selected_task_id) { throw "Deploy task selected." }

$missingPilot = Invoke-ApplyPilot -Name "missing-pilot" -Tasks @() -Extra @("-Preview")
if ($missingPilot.status -ne "no_safe_candidate") { throw "Missing pilot task should remain no_safe_candidate." }
if (@($missingPilot.blockers) -notcontains "no_safe_pilot_task") { throw "Missing pilot task should report no_safe_pilot_task." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "start-one-apply-pilot"
  scenarios = @(
    "apply_preview_does_not_claim",
    "seeded_pilot_task_is_accepted_by_apply_preview",
    "missing_risk_safe_pilot_allowed_with_hygiene_proof",
    "blocked_paths_guardrails_do_not_poison_safe_candidate",
    "heartbeat_only_worker_accepts_only_explicit_docs_compatibility_proof",
    "apply_requires_confirmation",
    "apply_refreshes_heartbeat_before_claim",
    "apply_claims_and_runs_once_fixture",
    "apply_rejects_old_failed_tasks",
    "apply_rejects_old_blocked_tasks",
    "apply_rejects_completed_tasks",
    "apply_rejects_multiple_candidates",
    "apply_rejects_unsafe_paths",
    "apply_rejects_deploy_secrets_server_root_tasks",
    "missing_pilot_task_remains_no_safe_candidate",
    "apply_reports_pilot_task_lookup_diagnostics",
    "apply_never_calls_run_until_hold",
    "project_control_remains_paused"
  )
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "start-one-apply-pilot"
}
