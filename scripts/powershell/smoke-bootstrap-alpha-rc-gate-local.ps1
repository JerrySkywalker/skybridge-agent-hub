$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1") -Command local -ApiBase "" -TokenFile "" -Json
if ($LASTEXITCODE -ne 0) { throw "RC gate local mode failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)
if ([string]$result.schema -ne "skybridge.bootstrap_alpha_rc_gate.v1") { throw "Unexpected RC gate schema." }
if ([string]$result.status -ne "pass") { throw "RC gate local mode should pass." }
Assert-True $result.local.ok "local.ok"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.deploy_mutation_performed "deploy_mutation_performed"
Assert-False $result.tag_created "tag_created"
Assert-False $result.token_printed "token_printed"

$missingRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-bootstrap-alpha-rc-gate.ps1") -Command local -ApiBase "" -TokenFile "" -FixtureMissingRequiredDocBlock -Json
$missingExit = $LASTEXITCODE
if ($missingExit -eq 0) { throw "RC gate missing doc block fixture should fail closed." }
$missing = (($missingRaw | Out-String).Trim() | ConvertFrom-Json)
if ([string]$missing.status -ne "blocked") { throw "Missing doc block should block RC gate." }
if (@($missing.blockers) -notcontains "missing_required_doc_blocks") { throw "Missing doc block blocker not reported." }
Assert-False $missing.task_claimed "missing.task_claimed"
Assert-False $missing.execution_started "missing.execution_started"
Assert-False $missing.token_printed "missing.token_printed"

[pscustomobject]@{
  ok = $true
  smoke = "bootstrap-alpha-rc-gate-local"
  local_status = [string]$result.status
  missing_doc_block_status = [string]$missing.status
  token_printed = $false
} | ConvertTo-Json
