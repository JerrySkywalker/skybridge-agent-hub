[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$pilotScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-safe-task-pilot.ps1")
$runnerScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-template-runner.ps1")

foreach ($needle in @(
  "MG332 live pilot is PowerShell-only for task live-safe-template-task-332-001",
  "MG332 live pilot status",
  "MG332 target task id",
  "MG332 cloud worker status",
  "MG332 evidence schema",
  "MG332 task claimed count",
  "MG332 old task claimed",
  "MG332 final task state",
  "MG332 live pilot preview",
  "MG332 live apply unavailable in Desktop",
  "LIVE_SAFE_TASK_PILOT_CREATE_CONFIRMATION_TEXT",
  "LIVE_SAFE_TASK_PILOT_RUN_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop live safe task pilot panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureLiveSafeTaskPilotPreview",
  "fixtureLiveSafeTaskPilotResult",
  "LIVE_SAFE_TASK_PILOT_TASK_ID",
  "live-safe-template-task-332-001",
  "skybridge.live_safe_template_task_evidence.v1",
  "task_claimed_count: 1",
  "old_task_claimed: false",
  "codex_run_called: false",
  "matlab_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "project_control_unpaused: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client live safe task pilot fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_SAFE_TEMPLATE_TASK_ONLY",
  "preview-create",
  "apply-create",
  "preview-run",
  "apply-run",
  "live-safe-template-task-332-001",
  "token_printed = `$false"
)) {
  if ($pilotScript -notmatch [regex]::Escape($needle)) {
    throw "Pilot script missing safety text: $needle"
  }
}

foreach ($needle in @(
  "preview-live-one",
  "apply-live-one",
  "create-live-safe-task-preview",
  "create-live-safe-task-apply",
  "max_tasks_exceeds_mg332_live_limit",
  "task_not_created_by_mg332_pilot",
  "skybridge.live_safe_template_task_evidence.v1",
  "old_task_claimed = `$false",
  "task_claimed_count",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($runnerScript -notmatch [regex]::Escape($needle)) {
    throw "Runner script missing MG332 safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-live-safe-task-pilot"
  target_task_id = "live-safe-template-task-332-001"
  desktop_live_apply_enabled = $false
  direct_run_button_enabled = $false
  arbitrary_shell_enabled = $false
  codex_run_called = $false
  matlab_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
