$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$expectedCommit = "4473257548bd0fc26e05002d968f8525b37bac8b"
$expectedImageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-4473257548bd0fc26e05002d968f8525b37bac8b"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1") -Command status -ApiBase "" -TokenFile "" -ExpectedCommit $expectedCommit -ExpectedImageRef $expectedImageRef -Json
if ($LASTEXITCODE -ne 0) { throw "RC gate status failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc_gate.v1") { throw "Unexpected RC gate schema." }
if ($result.status -notin @("pass", "warning")) { throw "RC gate status should pass or warn without live API." }
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.deploy_mutation_performed "deploy_mutation_performed"
Assert-False $result.tag_created "tag_created"
Assert-False $result.token_printed "token_printed"

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-rc-gate"
  status = [string]$result.status
  release_candidate_ready = [bool]$result.release_candidate_ready
  token_printed = $false
} | ConvertTo-Json
