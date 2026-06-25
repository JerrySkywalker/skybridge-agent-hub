$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

Assert-FileExists "docs/dev/CODEX_STOP_HOOK_HYGIENE.md"
$docText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs/dev/CODEX_STOP_HOOK_HYGIENE.md")
Assert-NoUnsafeText $docText

$result = Invoke-JsonScript "skybridge-bootstrap-alpha-rc1-handoff.ps1" @("-Command", "stop-hook-diagnose")

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc1_handoff.v1") { throw "Unexpected RC1 handoff schema." }
if ([string]$result.stop_hook_status -notin @("no_repo_hook_found", "repo_hook_ok", "repo_hook_timeout_risk", "local_codex_hook_not_repo_controlled", "fixed", "warning")) {
  throw "Unexpected stop hook status: $($result.stop_hook_status)"
}
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

[pscustomobject]@{
  ok = $true
  smoke = "codex-stop-hook-hygiene"
  stop_hook_status = [string]$result.stop_hook_status
  token_printed = $false
} | ConvertTo-Json
