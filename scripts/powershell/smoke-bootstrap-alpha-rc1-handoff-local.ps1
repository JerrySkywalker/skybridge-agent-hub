$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-bootstrap-alpha-rc1-handoff.ps1" @("-Command", "local")

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc1_handoff.v1") { throw "Unexpected RC1 handoff schema." }
if ([string]$result.status -notin @("pass", "warning")) { throw "RC1 handoff local status should be pass or warning." }
Assert-True $result.local.ok "local.ok"
Assert-True $result.handoff_doc_present "handoff_doc_present"
Assert-True $result.disabled_features_present "disabled_features_present"
Assert-False $result.github_release_created "github_release_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.project_control_unpaused "project_control_unpaused"
Assert-TokenPrintedFalse $result

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-rc1-handoff-local"
  status = [string]$result.status
  post_tag_audit_present = [bool]$result.post_tag_audit_present
  token_printed = $false
} | ConvertTo-Json
