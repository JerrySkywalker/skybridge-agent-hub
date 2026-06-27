. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-tool-provider.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
foreach ($forbidden in @("codex exec", "matlab -batch", "skybridge-run-once.ps1", "skybridge-worker-template-runner.ps1", "Start-Process", "Invoke-RestMethod", "New-Mcp")) {
  if ($source -match [regex]::Escape($forbidden)) { throw "Forbidden execution surface found: $forbidden" }
}

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "safe-summary", "-Fixture")
Assert-False $result.execution_allowed "execution_allowed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-no-execution"
