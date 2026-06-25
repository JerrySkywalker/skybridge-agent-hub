$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$expectedTag = "v0.1.0-bootstrap-alpha-rc1"
$expectedCommit = "4473257548bd0fc26e05002d968f8525b37bac8b"
$result = Invoke-JsonScript "skybridge-bootstrap-alpha-rc1-handoff.ps1" @("-Command", "tag", "-ExpectedTag", $expectedTag, "-ExpectedCommit", $expectedCommit)

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc1_handoff.v1") { throw "Unexpected RC1 handoff schema." }
Assert-True $result.tag_verified_local "tag_verified_local"
if ([string]$result.tag_target_commit -ne $expectedCommit) { throw "Tag target commit mismatch." }
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
  smoke = "bootstrap-alpha-rc1-tag-check"
  tag_name = [string]$result.tag_name
  tag_target_commit = [string]$result.tag_target_commit
  tag_verified_local = [bool]$result.tag_verified_local
  token_printed = $false
} | ConvertTo-Json
