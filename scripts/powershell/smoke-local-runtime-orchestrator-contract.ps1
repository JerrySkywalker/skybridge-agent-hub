. "$PSScriptRoot\smoke-productization-common.ps1"
$runtime = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "status")
if ($runtime.schema -ne "skybridge.local_runtime_orchestrator.v1") { throw "Unexpected runtime schema." }
foreach ($component in $runtime.components) {
  Assert-False $component.execution_enabled "component execution_enabled"
  Assert-False $component.queue_apply_enabled "component queue_apply_enabled"
  Assert-False $component.remote_execution_enabled "component remote_execution_enabled"
  Assert-False $component.arbitrary_command_enabled "component arbitrary_command_enabled"
  Assert-TokenPrintedFalse $component
}
Complete-Smoke "local-runtime-orchestrator-contract"
