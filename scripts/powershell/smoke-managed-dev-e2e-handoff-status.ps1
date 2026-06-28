. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-e2e-handoff.ps1" @(
  "-Command", "status"
)

if ($result.schema -ne "skybridge.managed_dev_e2e_handoff.v1") { throw "Unexpected handoff schema." }
if (@($result.capability_matrix).Count -ne 8) { throw "Expected M1-M8 capability matrix." }
Assert-True $result.required_docs_present "required_docs_present"
Assert-True $result.required_scripts_present "required_scripts_present"
Assert-True $result.required_smokes_present "required_smokes_present"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-e2e-handoff-status"
