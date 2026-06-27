. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-multi-goal-loop.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
foreach ($pattern in @("Start-Process", "Invoke-Expression", "Invoke-Command", "codex\s+(exec|run)", "matlab\s+(-batch|-r)", 'mcp_run_called\s*=\s*\$true', 'worker_loop_started\s*=\s*\$true', 'project_control_unpaused\s*=\s*\$true')) {
  if ($source -match $pattern) { throw "Unsafe execution surface found in source: $pattern" }
}

$result = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-Confirm", "I_UNDERSTAND_RUN_ONE_STATIC_MULTI_GOAL_STEP_ONLY", "-OutputDir", ".agent/tmp/multi-goal-loop-smoke-no-worker-$([guid]::NewGuid().ToString('N'))")
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.arbitrary_shell_enabled "arbitrary_shell_enabled"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "multi-goal-loop-no-worker-loop"
