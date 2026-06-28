. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-stage-s1-1-close.ps1" @(
  "-Command", "audit"
)

if ($result.schema -ne "skybridge.stage_s1_1_close.v1") { throw "Unexpected stage close schema." }
Assert-True $result.required_docs_present "required_docs_present"
Assert-True $result.required_scripts_present "required_scripts_present"
Assert-True $result.required_smokes_present "required_smokes_present"
if (@($result.stage_capabilities).Count -lt 13) { throw "Stage capability summary is incomplete." }
if (@($result.tracked_warnings).Count -lt 1) { throw "Tracked warning must be reported." }
if (@($result.resolved_warnings).Count -lt 1) { throw "Resolved warning must be reported." }
if (@($result.blockers).Count -ne 0) { throw "Stage close audit reported blockers." }
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.queue_runner_started "queue_runner_started"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_live_called "hermes_live_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "stage-s1-1-close-audit"
