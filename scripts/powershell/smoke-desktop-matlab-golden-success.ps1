[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$successScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-matlab-golden-success.ps1")

foreach ($needle in @(
  "MG336 MATLAB golden success is PowerShell-only for task live-matlab-golden-task-336-001",
  "MG336 MATLAB Golden Success status",
  "MG336 success task id",
  "MG336 doctor precondition",
  "MG336 tiny grid",
  "MG336 expected combinations",
  "MG336 manifest exists",
  "MG336 summary exists",
  "MG336 metrics exists",
  "MG336 evidence validation",
  "MG336 success preview",
  "MG336 success apply unavailable in Desktop",
  "MATLAB_GOLDEN_SUCCESS_CREATE_CONFIRMATION_TEXT",
  "MATLAB_GOLDEN_SUCCESS_RUN_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop MATLAB golden success panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureMatlabGoldenSuccessRunnerPreview",
  "fixtureMatlabGoldenSuccessEvidence",
  "fixtureMatlabGoldenSuccessPreview",
  "MATLAB_GOLDEN_SUCCESS_TASK_ID",
  "live-matlab-golden-task-336-001",
  "expected_combination_count",
  "manifest_exists",
  "summary_exists",
  "metrics_exists",
  "raw_stdout_included: false",
  "raw_stderr_included: false",
  "codex_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "project_control_unpaused: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client MATLAB success fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_SUCCESS_TASK_ONLY",
  "live-matlab-golden-task-336-001",
  "live-matlab-golden-task-333-001",
  "live-matlab-golden-task-334-001",
  "mg333_mg334_failed_tasks_must_not_be_reused",
  "task_not_created_by_mg336_success",
  "doctor_precondition_passed",
  "expected_combination_count",
  "manifest_exists",
  "summary_exists",
  "metrics_exists",
  "old_task_claimed = `$false",
  "codex_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($successScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB success script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-matlab-golden-success"
  target_task_id = "live-matlab-golden-task-336-001"
  desktop_live_apply_enabled = $false
  arbitrary_matlab_command_box = $false
  arbitrary_shell_enabled = $false
  codex_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
