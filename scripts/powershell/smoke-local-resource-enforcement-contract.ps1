. "$PSScriptRoot/smoke-local-resource-enforcement-common.ps1"
$gate = Invoke-LocalResourceJson "enforcement-gate"
if ($gate.schema -ne "skybridge.local_resource_policy_enforcement.v1") { throw "Unexpected enforcement schema." }
if ($gate.policy.schema -ne "skybridge.local_resource_policy.v1") { throw "Unexpected policy schema." }
if ($gate.observation.schema -ne "skybridge.local_resource_observation.v1") { throw "Unexpected observation schema." }
if ($gate.no_powercfg_mutation -ne $true -or $gate.admin_required -ne $false) { throw "Gate must be no-mutation and non-admin." }
if ($gate.task_claimed -ne $false -or $gate.task_executed -ne $false) { throw "Gate must not claim or execute tasks." }
Assert-LocalResourceSafeJson $gate
Write-LocalResourceSmokeResult "local-resource-enforcement-contract"
