. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "safe-summary"
)

if ($result.schema -ne "skybridge.hermes_planner_provider.v1") { throw "Unexpected Hermes planner provider schema." }
if ($result.provider_name -ne "hermes") { throw "Unexpected provider name." }
if ($result.provider_role -ne "planner") { throw "Unexpected provider role." }
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-status"
