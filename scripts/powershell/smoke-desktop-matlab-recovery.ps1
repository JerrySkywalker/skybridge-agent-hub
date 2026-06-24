[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$doctorScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-matlab-doctor.ps1")
$recoveryScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-matlab-golden-recovery.ps1")

foreach ($needle in @(
  "MG334 MATLAB recovery is PowerShell-only for task live-matlab-golden-task-334-001",
  "MG334 MATLAB doctor status",
  "MG334 doctor failure category",
  "MG334 recovery task id",
  "MG334 recovery evidence summary",
  "MG334 recovery existing outputs",
  "MG334 recovery expected outputs missing",
  "MG334 MATLAB doctor preview",
  "MG334 recovery preview",
  "MG334 recovery apply unavailable in Desktop",
  "MATLAB_DOCTOR_CONFIRMATION_TEXT",
  "MATLAB_GOLDEN_RECOVERY_CREATE_CONFIRMATION_TEXT",
  "MATLAB_GOLDEN_RECOVERY_RUN_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop MATLAB recovery panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureMatlabDoctorPreview",
  "fixtureMatlabRecoveryRunnerPreview",
  "fixtureMatlabRecoveryEvidence",
  "fixtureMatlabRecoveryPreview",
  "MATLAB_GOLDEN_RECOVERY_TASK_ID",
  "live-matlab-golden-task-334-001",
  "existing_outputs",
  "expected_outputs_missing",
  "failure_category",
  "raw_stdout_included: false",
  "raw_stderr_included: false",
  "codex_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "project_control_unpaused: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client MATLAB recovery fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_RUN_FIXED_MATLAB_STARTUP_DIAGNOSTIC_ONLY",
  "skybridge.matlab_doctor.v1",
  "skybridge_matlab_startup_doctor.m",
  "raw_stdout_included = `$false",
  "raw_stderr_included = `$false",
  "token_printed = `$false"
)) {
  if ($doctorScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB doctor script missing safety text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_RECOVERY_TASK_ONLY",
  "live-matlab-golden-task-334-001",
  "live-matlab-golden-task-333-001",
  "mg333_failed_task_must_not_be_reused",
  "task_not_created_by_mg334_recovery",
  "MATLAB doctor failed; no live recovery task was claimed.",
  "old_task_claimed = `$false",
  "codex_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($recoveryScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB recovery script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-matlab-recovery"
  target_task_id = "live-matlab-golden-task-334-001"
  desktop_live_apply_enabled = $false
  arbitrary_matlab_command_box = $false
  arbitrary_shell_enabled = $false
  codex_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
