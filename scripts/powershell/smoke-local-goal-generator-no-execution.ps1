. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-local-goal-generator.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
foreach ($pattern in @("Start-Process", "Invoke-Expression", "Invoke-Command", "skybridge-goal-loop\.ps1", "skybridge-multi-goal-loop\.ps1", 'project_control_unpaused\s*=\s*\$true', 'worker_loop_started\s*=\s*\$true', 'matlab_run_called\s*=\s*\$true', 'hermes_run_called\s*=\s*\$true', 'mcp_run_called\s*=\s*\$true')) {
  if ($source -match $pattern) { throw "Unsafe execution surface found in source: $pattern" }
}

$outputDir = ".agent/tmp/generated-goals/smoke-no-execution-$([guid]::NewGuid().ToString('N'))"
$confirm = "I_UNDERSTAND_GENERATE_ONE_GOAL_MARKDOWN_ONLY_NO_IMPORT_NO_EXECUTION"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "generate-one", "-Fixture", "-OutputDir", $outputDir, "-Confirm", $confirm)
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.raw_stdout_persisted "raw_stdout_persisted"
Assert-False $result.raw_stderr_persisted "raw_stderr_persisted"
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-no-execution"
