. "$PSScriptRoot\smoke-productization-common.ps1"
$guide = Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "action-guide")
if ($guide.schema -ne "skybridge.local_doctor_action_guide.v1") { throw "schema mismatch" }
foreach ($action in @($guide.actions)) {
  Assert-False $action.destructive_action_required "destructive_action_required"
  Assert-False $action.host_mutation_required "host_mutation_required"
}
Assert-TokenPrintedFalse $guide
Complete-Smoke "local-doctor-action-guide"
