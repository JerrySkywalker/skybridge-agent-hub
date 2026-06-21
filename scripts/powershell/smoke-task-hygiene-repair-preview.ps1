[CmdletBinding()]
param(
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\task-hygiene-repair-preview-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null
$fixturePath = Join-Path $tmpRoot "hygiene.json"

$unsafeTasks = @(
  "unsafe-failed-001",
  "unsafe-failed-002",
  "unsafe-failed-003",
  "unsafe-failed-004",
  "unsafe-failed-005",
  "unsafe-failed-006",
  "unsafe-failed-007",
  "unsafe-failed-008",
  "unsafe-failed-009",
  "unsafe-failed-010",
  "unsafe-failed-011"
)

$hygiene = [pscustomobject]@{
  schema = "skybridge.task_hygiene_report.v1"
  ok = $true
  project_id = "skybridge-agent-hub"
  total_tasks = 18
  failed_unrecovered = 11
  blocked = 3
  needs_evidence = 1
  stale_leases = 0
  stale_claims = 0
  safe_requeue_candidates = @()
  evidence_repair_candidates = @(
    [pscustomobject]@{ task_id = "remote-docs-exec-pilot-001"; classification = "evidence-repair-only" }
  )
  archive_or_keep_blocked_candidates = @(
    [pscustomobject]@{ task_id = "always-on-worker-loop-pilot-docs-179"; classification = "historical-residue" },
    [pscustomobject]@{ task_id = "task_proposal-59a0236fb69800cd"; classification = "historical-residue" },
    [pscustomobject]@{ task_id = "remote-claim-smoke-001"; classification = "historical-residue" }
  )
  unsafe_to_requeue_candidates = @($unsafeTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "unsafe-to-requeue" } })
  safety = [pscustomobject]@{
    tasks_mutated = $false
    tasks_claimed = $false
    tasks_requeued = $false
    tasks_cancelled = $false
    evidence_written = $false
    codex_run_called = $false
    token_printed = $false
  }
  token_printed = $false
}
$hygiene | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fixturePath -Encoding UTF8

$raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-task-hygiene-repair-preview.ps1") `
  -ProjectId "skybridge-agent-hub" `
  -FixtureHygieneFile $fixturePath `
  -Json
if ($LASTEXITCODE -ne 0) { throw "repair preview script failed." }
$text = (($raw | Out-String).Trim())
Assert-NoUnsafeText $text
if ($text -match "fixture raw prompt|fixture raw log|raw_hermes_response") { throw "Raw unsafe marker leaked." }
$result = $text | ConvertFrom-Json

if ($result.schema -ne "skybridge.task_hygiene_repair_preview.v1") { throw "Unexpected repair preview schema." }
Assert-True $result.ok "ok"
Assert-True $result.preview_only "preview_only"
Assert-False $result.token_printed "token_printed"
Assert-False $result.tasks_mutated "tasks_mutated"
Assert-False $result.tasks_claimed "tasks_claimed"
Assert-False $result.tasks_requeued "tasks_requeued"
Assert-False $result.tasks_cancelled "tasks_cancelled"
Assert-False $result.tasks_archived "tasks_archived"
Assert-False $result.evidence_written "evidence_written"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.queue_apply_called "queue_apply_called"

if (@($result.evidence_repair_preview).Count -ne 1) { throw "Expected one evidence repair preview." }
if (@($result.archive_or_keep_blocked_preview).Count -ne 3) { throw "Expected three archive-or-keep-blocked previews." }
if (@($result.unsafe_to_requeue_exclusions).Count -ne 11) { throw "Expected eleven unsafe-to-requeue exclusions." }

$evidence = @($result.evidence_repair_preview)[0]
if ($evidence.task_id -ne "remote-docs-exec-pilot-001") { throw "Unexpected evidence repair task." }
foreach ($required in @("create a new PR", "requeue the task", "rerun Codex", "claim the task")) {
  if (@($evidence.must_not) -notcontains $required) { throw "Evidence preview missing must_not: $required" }
}

foreach ($taskId in @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001")) {
  if (@($result.archive_or_keep_blocked_preview | Where-Object { $_.task_id -eq $taskId }).Count -ne 1) {
    throw "Missing blocked preview for $taskId."
  }
}
foreach ($taskId in $unsafeTasks) {
  $match = @($result.unsafe_to_requeue_exclusions | Where-Object { $_.task_id -eq $taskId })
  if ($match.Count -ne 1) { throw "Missing unsafe exclusion for $taskId." }
  Assert-True $match[0].excluded_from_worker_scheduling "excluded_from_worker_scheduling"
}

$summary = [pscustomobject]@{
  ok = $true
  smoke = "task-hygiene-repair-preview"
  evidence_repair_preview = @($result.evidence_repair_preview).Count
  archive_or_keep_blocked_preview = @($result.archive_or_keep_blocked_preview).Count
  unsafe_to_requeue_exclusions = @($result.unsafe_to_requeue_exclusions).Count
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "task-hygiene-repair-preview"
}
