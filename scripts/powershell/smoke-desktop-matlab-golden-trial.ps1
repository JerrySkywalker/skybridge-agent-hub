[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$runnerScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-matlab-parameter-sweep-runner.ps1")
$trialScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-matlab-golden-trial.ps1")

foreach ($needle in @(
  "MG333 MATLAB golden trial is PowerShell-only for task live-matlab-golden-task-333-001",
  "MG333 MATLAB Golden Trial status",
  "MG333 target task id",
  "MG333 cloud worker status",
  "MG333 parameter grid",
  "MG333 combination count",
  "MG333 MATLAB capability detected",
  "MG333 preview matlab_invoked",
  "MG333 output dir",
  "MG333 manifest path",
  "MG333 summary path",
  "MG333 metrics path",
  "MG333 raw_stdout_included",
  "MG333 raw_stderr_included",
  "MG333 raw_mat_files_uploaded",
  "MG333 MATLAB golden preview",
  "MG333 MATLAB apply unavailable in Desktop",
  "MATLAB_GOLDEN_TRIAL_CREATE_CONFIRMATION_TEXT",
  "MATLAB_GOLDEN_TRIAL_RUN_CONFIRMATION_TEXT",
  "MATLAB_PARAMETER_SWEEP_RUNNER_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop MATLAB golden trial panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureMatlabGoldenRunnerPreview",
  "fixtureMatlabGoldenEvidence",
  "fixtureMatlabGoldenTrialPreview",
  "MATLAB_GOLDEN_TRIAL_TASK_ID",
  "live-matlab-golden-task-333-001",
  "matlab-parameter-sweep.v1",
  "matlab-parameter-sweep-runner.v1",
  "skybridge.matlab_sweep_evidence.v1",
  "raw_stdout_included: false",
  "raw_stderr_included: false",
  "raw_mat_files_uploaded: false",
  "codex_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "project_control_unpaused: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client MATLAB golden trial fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_RUN_ONE_FIXED_MATLAB_SWEEP_ONLY",
  "skybridge_run_parameter_sweep.m",
  "parameter_grid_too_large",
  "arbitrary_command_text_detected",
  "output_dir_outside_allowed_paths",
  "raw_stdout_included = `$false",
  "raw_stderr_included = `$false",
  "raw_mat_files_uploaded = `$false",
  "codex_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "token_printed = `$false"
)) {
  if ($runnerScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB runner script missing safety text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_MATLAB_GOLDEN_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_MATLAB_GOLDEN_TASK_ONLY",
  "live-matlab-golden-task-333-001",
  "matlab-parameter-sweep.v1",
  "matlab-parameter-sweep-runner.v1",
  "task_not_created_by_mg333_golden_trial",
  "matlab_not_available",
  "old_task_claimed = `$false",
  "codex_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($trialScript -notmatch [regex]::Escape($needle)) {
    throw "MATLAB golden trial script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-matlab-golden-trial"
  target_task_id = "live-matlab-golden-task-333-001"
  desktop_live_apply_enabled = $false
  arbitrary_matlab_command_box = $false
  arbitrary_shell_enabled = $false
  codex_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
