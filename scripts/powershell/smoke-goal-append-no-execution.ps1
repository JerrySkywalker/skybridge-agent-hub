. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-goal-append.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
foreach ($pattern in @("Start-Process", "Invoke-Expression", "Invoke-Command", "codex\s+(exec|run)", "matlab\s+(-batch|-r)", 'project_control_unpaused\s*=\s*\$true', 'worker_loop_started\s*=\s*\$true', 'codex_run_called\s*=\s*\$true', 'matlab_run_called\s*=\s*\$true', 'hermes_run_called\s*=\s*\$true', 'mcp_run_called\s*=\s*\$true')) {
  if ($source -match $pattern) { throw "Unsafe execution surface found in source: $pattern" }
}

$outputDir = ".agent/tmp/goal-append/smoke-no-execution-$([guid]::NewGuid().ToString('N'))"
$approveConfirm = "I_UNDERSTAND_APPROVE_ONE_GENERATED_GOAL_FOR_REVIEW_ONLY_NO_EXECUTION"
$appendConfirm = "I_UNDERSTAND_APPEND_ONE_REVIEWED_GOAL_STEP_ONLY_NO_EXECUTION"
Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "approve",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-ApprovalReason", "Operator approved fixture metadata review only.",
  "-Confirm", $approveConfirm
) | Out-Null
$result = Invoke-JsonScript "skybridge-goal-append.ps1" @(
  "-Command", "append-apply",
  "-Fixture",
  "-OutputDir", $outputDir,
  "-AppendReason", "Operator appended fixture metadata only.",
  "-Confirm", $appendConfirm
)
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-False $result.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.raw_stdout_persisted "raw_stdout_persisted"
Assert-False $result.raw_stderr_persisted "raw_stderr_persisted"
Assert-TokenPrintedFalse $result

Complete-Smoke "goal-append-no-execution"
