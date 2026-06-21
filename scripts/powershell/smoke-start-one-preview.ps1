[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\start-one-preview-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Invoke-Preview {
  param([string]$Name, $Tasks, $Workers, $Hygiene, $SecondGate)
  $tasksPath = Write-Fixture "$Name-tasks.json" ([pscustomobject]@{ tasks = @($Tasks) })
  $workersPath = Write-Fixture "$Name-workers.json" ([pscustomobject]@{ workers = @($Workers) })
  $hygienePath = Write-Fixture "$Name-hygiene.json" $Hygiene
  $gatePath = Write-Fixture "$Name-second-gate.json" $SecondGate
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-start-one-preview.ps1 `
    -ProjectId "skybridge-agent-hub" `
    -FixtureTasksFile $tasksPath `
    -FixtureWorkersFile $workersPath `
    -FixtureHygieneFile $hygienePath `
    -FixtureSecondGateFile $gatePath `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "start-one preview script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.start_one_preview.v1") { throw "Unexpected schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  return $result
}

function New-Task {
  param(
    [string]$TaskId,
    [string]$Status = "queued",
    [string]$Risk = "low",
    [string]$TaskType = "docs",
    [string[]]$Capabilities = @("codex"),
    $HygieneMetadata = $null
  )
  $task = [ordered]@{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = "Safe summary for $TaskId"
    status = $Status
    risk = $Risk
    task_type = $TaskType
    source = "manual"
    required_capabilities = @($Capabilities)
    allowed_paths = @("docs/**")
    hygiene_metadata = $HygieneMetadata
    token_printed = $false
  }
  [pscustomobject]$task
}

$worker = [pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "online"; enabled = $true; capabilities = @("codex", "docs"); token_printed = $false }
$secondGate = [pscustomobject]@{
  schema = "skybridge.execution_second_gate_readiness.v1"
  ok = $true
  status = "preview_ready"
  allowed_preview_only = $true
  allowed_execution = $false
  project_control_state = "paused"
  hermes_tool_execution_risk = $true
  second_gate_configured = $false
  token_printed = $false
}
$unsafeTasks = 1..12 | ForEach-Object { "unsafe-to-requeue-$($_)" }
$blockedTasks = @("always-on-worker-loop-pilot-docs-179", "task_proposal-59a0236fb69800cd", "remote-claim-smoke-001")
$hygiene = [pscustomobject]@{
  schema = "skybridge.task_hygiene_report.v1"
  ok = $true
  unsafe_to_requeue_candidates = @($unsafeTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "unsafe-to-requeue" } })
  archive_or_keep_blocked_candidates = @($blockedTasks | ForEach-Object { [pscustomobject]@{ task_id = $_; classification = "historical-residue" } })
  token_printed = $false
}

$tasks = @()
$tasks += @($unsafeTasks | ForEach-Object { New-Task -TaskId $_ -Status "failed" -Risk "low" })
$tasks += @($blockedTasks | ForEach-Object { New-Task -TaskId $_ -Status "blocked" -Risk "low" })
$tasks += New-Task -TaskId "remote-docs-exec-pilot-001" -Status "failed" -Risk "low" -HygieneMetadata ([pscustomobject]@{ excluded_from_worker_scheduling = $true; history = @([pscustomobject]@{ operation = "mark_excluded_from_requeue"; excluded_from_requeue = $true }) })
$tasks += New-Task -TaskId "completed-residue-317" -Status "completed" -Risk "low"
$tasks += New-Task -TaskId "high-risk-production-deploy" -Status "queued" -Risk "high" -TaskType "deploy"
$tasks += New-Task -TaskId "hygiene-excluded-queued" -Status "queued" -Risk "low" -HygieneMetadata ([pscustomobject]@{ excluded_from_worker_scheduling = $true })

$noSafe = Invoke-Preview -Name "no-safe" -Tasks $tasks -Workers @($worker) -Hygiene $hygiene -SecondGate $secondGate
if ($noSafe.status -ne "no_safe_candidate") { throw "Expected no_safe_candidate." }
if ($null -ne $noSafe.selected_candidate) { throw "No-safe fixture selected a candidate." }
Assert-False $noSafe.would_claim "no-safe would_claim"
Assert-False $noSafe.would_run_codex "no-safe would_run_codex"
Assert-False $noSafe.would_unpause_project_control "no-safe would_unpause"
if ($noSafe.excluded_tasks_summary.unsafe_to_requeue_tasks_excluded -ne 12) { throw "Expected 12 unsafe-to-requeue exclusions." }
if ($noSafe.excluded_tasks_summary.blocked_historical_tasks_excluded -ne 3) { throw "Expected 3 blocked historical exclusions." }
Assert-True $noSafe.excluded_tasks_summary.remote_docs_exec_pilot_001_excluded "remote-docs exclusion"
if ($noSafe.excluded_tasks_summary.goal_315_317_residue_eligible -ne 0) { throw "Goal 315/317 residue became eligible." }

$safeTask = New-Task -TaskId "docs-low-risk-safe-queued-318" -Status "queued" -Risk "low" -TaskType "docs"
$candidate = Invoke-Preview -Name "candidate" -Tasks (@($tasks) + @($safeTask)) -Workers @($worker) -Hygiene $hygiene -SecondGate $secondGate
if ($candidate.status -ne "candidate_previewed") { throw "Expected candidate_previewed." }
if ($candidate.selected_candidate.task_id -ne "docs-low-risk-safe-queued-318") { throw "Unexpected selected candidate." }
Assert-False $candidate.would_claim "candidate would_claim"
Assert-False $candidate.would_run_codex "candidate would_run_codex"

$blockedGate = $secondGate | ConvertTo-Json -Depth 16 | ConvertFrom-Json
$blockedGate.allowed_preview_only = $false
$blockedGate.status = "blocked"
$blockedPreview = Invoke-Preview -Name "blocked-gate" -Tasks @($safeTask) -Workers @($worker) -Hygiene $hygiene -SecondGate $blockedGate
if ($blockedPreview.status -ne "second_gate_preview_blocked") { throw "Expected second_gate_preview_blocked." }
if ($null -ne $blockedPreview.selected_candidate) { throw "Blocked second gate selected a candidate." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "start-one-preview"
  scenarios = @(
    [pscustomobject]@{ name = "no_safe_candidate"; status = $noSafe.status; unsafe_excluded = $noSafe.excluded_tasks_summary.unsafe_to_requeue_tasks_excluded; blocked_excluded = $noSafe.excluded_tasks_summary.blocked_historical_tasks_excluded },
    [pscustomobject]@{ name = "candidate_previewed_without_claim"; status = $candidate.status; selected = $candidate.selected_candidate.task_id },
    [pscustomobject]@{ name = "second_gate_blocks_preview"; status = $blockedPreview.status }
  )
  would_claim = $false
  would_run_codex = $false
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "start-one-preview"
}
