[CmdletBinding()]
param(
  [int]$Port = 0,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

function Invoke-SkyBridgeJson([string]$Method, [string]$Path, $Body = $null) {
  $uri = "$ApiBase$Path"
  if ($null -eq $Body) {
    if ($Method -in @("POST", "PATCH")) { return Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body "{}" }
    return Invoke-RestMethod -Method $Method -Uri $uri
  }
  Invoke-RestMethod -Method $Method -Uri $uri -ContentType "application/json" -Body ($Body | ConvertTo-Json -Depth 20)
}

function Wait-SkyBridgeHealth {
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try { Invoke-SkyBridgeJson "GET" "/v1/health" | Out-Null; return } catch { Start-Sleep -Milliseconds 500 }
  }
  throw "SkyBridge server did not become healthy at $ApiBase."
}

function Invoke-HygieneApply {
  param([string[]]$ScriptArgs, [switch]$ExpectFailure)
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-task-hygiene-apply.ps1") @ScriptArgs 2>&1
  $exit = $LASTEXITCODE
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  if ($ExpectFailure) {
    if ($exit -eq 0) { throw "Expected hygiene apply command to fail." }
    return $text
  }
  if ($exit -ne 0) { throw "Hygiene apply command failed: $text" }
  return ($text | ConvertFrom-Json)
}

function Get-TaskMap {
  $response = Invoke-SkyBridgeJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  $map = @{}
  foreach ($task in @($response.tasks)) { $map[[string]$task.task_id] = $task }
  $map
}

$serverProcess = $null
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-task-hygiene-apply-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
$dbFile = Join-Path $tempDir "skybridge-task-hygiene-apply.sqlite"
if ($Port -le 0) { $Port = Get-Random -Minimum 18000 -Maximum 28000 }
$ApiBase = "http://127.0.0.1:$Port"

try {
  $serverCommand = "`$env:SKYBRIDGE_DB_FILE = '$dbFile'; `$env:PORT = '$Port'; Remove-Item Env:SKYBRIDGE_WORKER_TOKEN -ErrorAction SilentlyContinue; Remove-Item Env:SKYBRIDGE_WORKER_TOKENS_FILE -ErrorAction SilentlyContinue; corepack pnpm --filter @skybridge-agent-hub/server dev"
  $startProcessParams = @{ FilePath = "pwsh"; ArgumentList = @("-NoProfile", "-Command", $serverCommand); PassThru = $true }
  if ($IsWindows) { $startProcessParams.WindowStyle = "Hidden" }
  $serverProcess = Start-Process @startProcessParams
  Wait-SkyBridgeHealth

  Invoke-SkyBridgeJson "POST" "/v1/projects" @{ project_id = "skybridge-agent-hub"; name = "SkyBridge Agent Hub" } | Out-Null
  Invoke-SkyBridgeJson "PATCH" "/v1/projects/skybridge-agent-hub/control" @{ state = "paused"; stop_requested = $false; stop_reason = "goal_317_fixture" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/register" @{ worker_id = "goal-317-worker"; name = "Goal 317 Fixture Worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/workers/goal-317-worker/heartbeat" @{ status_note = "metadata fixture" } | Out-Null

  $evidenceTask = "remote-docs-exec-pilot-001"
  $blockedTasks = @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001")
  $unsafeTasks = 1..11 | ForEach-Object { "unsafe-to-requeue-$($_)" }

  Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = $evidenceTask; project_id = "skybridge-agent-hub"; title = "Evidence repair fixture"; risk = "low"; task_type = "docs"; source = "manual" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/$evidenceTask/claim" @{ worker_id = "goal-317-worker" } | Out-Null
  Invoke-SkyBridgeJson "POST" "/v1/tasks/$evidenceTask/fail" @{ worker_id = "goal-317-worker"; error_summary = "merged pr needs evidence"; pr_url = "https://github.com/example/repo/pull/316" } | Out-Null

  foreach ($taskId in $blockedTasks) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = $taskId; project_id = "skybridge-agent-hub"; title = "Blocked fixture $taskId"; risk = "low"; task_type = "docs"; source = "manual" } | Out-Null
    Invoke-SkyBridgeJson "POST" "/v1/tasks/$taskId/block" @{ error_summary = "historical keep-blocked" } | Out-Null
  }
  foreach ($taskId in $unsafeTasks) {
    Invoke-SkyBridgeJson "POST" "/v1/tasks" @{ task_id = $taskId; project_id = "skybridge-agent-hub"; title = "Unsafe requeue fixture $taskId"; risk = "low"; task_type = "docs"; source = "manual" } | Out-Null
    Invoke-SkyBridgeJson "POST" "/v1/tasks/$taskId/claim" @{ worker_id = "goal-317-worker" } | Out-Null
    Invoke-SkyBridgeJson "POST" "/v1/tasks/$taskId/fail" @{ worker_id = "goal-317-worker"; error_summary = "manual review required before retry" } | Out-Null
  }

  $preview = Invoke-HygieneApply -ScriptArgs @("-ApiBase", $ApiBase, "-Preview", "-Json")
  if ($preview.schema -ne "skybridge.task_hygiene_apply.v1") { throw "Unexpected schema." }
  Assert-True $preview.ok "preview ok"
  if ($preview.mode -ne "preview") { throw "Preview mode expected." }
  Assert-False $preview.safety.tasks_mutated "preview tasks_mutated"
  Assert-False $preview.safety.tasks_claimed "preview tasks_claimed"
  Assert-False $preview.safety.tasks_requeued "preview tasks_requeued"
  Assert-False $preview.safety.codex_run_called "preview codex_run_called"
  Assert-False $preview.safety.project_control_unpaused "preview project_control_unpaused"
  Assert-False $preview.token_printed "preview token_printed"
  if (@($preview.planned_actions.evidence_repair_actions).Count -ne 1) { throw "Expected one evidence repair action." }
  if (@($preview.planned_actions.archive_or_keep_blocked_actions).Count -ne 3) { throw "Expected three blocked actions." }
  if (@($preview.planned_actions.unsafe_to_requeue_exclusion_actions).Count -ne 11) { throw "Expected eleven unsafe exclusion actions." }

  $defaultPreview = Invoke-HygieneApply -ScriptArgs @("-ApiBase", $ApiBase, "-Json")
  if ($defaultPreview.mode -ne "preview") { throw "Default mode must be preview." }

  Invoke-HygieneApply -ScriptArgs @("-ApiBase", $ApiBase, "-Apply", "-Json") -ExpectFailure | Out-Null

  $badFixture = Join-Path $tempDir "unexpected-hygiene.json"
  [pscustomobject]@{
    schema = "skybridge.task_hygiene_report.v1"
    ok = $true
    evidence_repair_candidates = @([pscustomobject]@{ task_id = "unexpected-task"; classification = "evidence-repair-only" })
    archive_or_keep_blocked_candidates = @($blockedTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "historical-residue" } })
    unsafe_to_requeue_candidates = @($unsafeTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "unsafe-to-requeue" } })
    token_printed = $false
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badFixture -Encoding UTF8
  Invoke-HygieneApply -ScriptArgs @("-ApiBase", $ApiBase, "-FixtureHygieneFile", $badFixture, "-Apply", "-Confirm", "I_UNDERSTAND_GOAL_317_HYGIENE_METADATA_ONLY", "-Json") -ExpectFailure | Out-Null

  try {
    Invoke-SkyBridgeJson "POST" "/v1/tasks/$evidenceTask/hygiene-metadata" @{ project_id = "skybridge-agent-hub"; operation = "mark_evidence_repair_applied"; requested_status = "queued"; reason = "must fail" } | Out-Null
    throw "Expected forbidden status transition to fail."
  } catch {
    if ($_.Exception.Message -notmatch "400") { throw }
  }

  $before = Get-TaskMap
  $apply = Invoke-HygieneApply -ScriptArgs @("-ApiBase", $ApiBase, "-Apply", "-Confirm", "I_UNDERSTAND_GOAL_317_HYGIENE_METADATA_ONLY", "-Json")
  Assert-True $apply.ok "apply ok"
  if ($apply.mode -ne "apply") { throw "Apply mode expected." }
  Assert-False $apply.safety.tasks_claimed "apply tasks_claimed"
  Assert-False $apply.safety.tasks_requeued "apply tasks_requeued"
  Assert-False $apply.safety.codex_run_called "apply codex_run_called"
  Assert-False $apply.safety.project_control_unpaused "apply project_control_unpaused"
  Assert-False $apply.token_printed "apply token_printed"
  if (@($apply.applied_actions).Count -ne 15) { throw "Expected fifteen metadata-only applied actions." }

  $after = Get-TaskMap
  foreach ($taskId in @($evidenceTask) + $blockedTasks + $unsafeTasks) {
    if ([string]$after[$taskId].status -in @("queued", "claimed", "running")) { throw "Task $taskId entered an execution status." }
    if ([string]$after[$taskId].status -ne [string]$before[$taskId].status) { throw "Task $taskId status changed." }
    if ([string]$after[$taskId].assigned_worker_id -ne [string]$before[$taskId].assigned_worker_id) { throw "Task $taskId worker assignment changed." }
    if ($null -eq $after[$taskId].hygiene_metadata) { throw "Task $taskId missing hygiene metadata after apply." }
  }
  $evidence = $after[$evidenceTask]
  if ($null -eq $evidence.result.evidence_summary -or $evidence.result.evidence_summary.recovered -ne $true) { throw "Evidence metadata was not repaired." }
  foreach ($taskId in $blockedTasks + $unsafeTasks) {
    if ($after[$taskId].hygiene_metadata.excluded_from_worker_scheduling -ne $true) { throw "Task $taskId was not excluded from worker scheduling." }
  }
  $control = Invoke-SkyBridgeJson "GET" "/v1/projects/skybridge-agent-hub/control"
  if ($control.control_state.state -ne "paused") { throw "project_control did not remain paused." }

  $rawApply = $apply | ConvertTo-Json -Depth 40
  if ($rawApply -match "raw_worker_log|raw_prompt|raw_hermes_response|raw_notification_payload") { throw "Raw payload marker leaked." }

  $summary = [pscustomobject]@{
    ok = $true
    smoke = "task-hygiene-apply"
    preview_default = $true
    apply_failed_without_confirmation = $true
    unexpected_task_ids_rejected = $true
    forbidden_status_transition_rejected = $true
    metadata_only_applied_actions = @($apply.applied_actions).Count
    project_control_state = $control.control_state.state
    token_printed = $false
  }
  if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "task-hygiene-apply" }
} finally {
  if ($serverProcess) {
    try { $serverProcess.Kill($true) } catch { Stop-Process -Id $serverProcess.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
