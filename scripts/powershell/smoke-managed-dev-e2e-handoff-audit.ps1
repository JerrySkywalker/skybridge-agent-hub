. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-e2e-handoff.ps1" @(
  "-Command", "audit"
)

if ($result.schema -ne "skybridge.managed_dev_e2e_handoff.v1") { throw "Unexpected handoff schema." }
if ([string]::IsNullOrWhiteSpace($result.expected_commit)) { throw "Expected commit must be reported." }
if ([string]::IsNullOrWhiteSpace($result.expected_cloud_image)) { throw "Expected cloud image must be reported." }
Assert-True $result.required_docs_present "required_docs_present"
Assert-True $result.required_scripts_present "required_scripts_present"
Assert-True $result.required_smokes_present "required_smokes_present"
if (@($result.blockers).Count -ne 0) { throw "Audit reported blockers." }
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.queue_runner_started "queue_runner_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-e2e-handoff-audit"
