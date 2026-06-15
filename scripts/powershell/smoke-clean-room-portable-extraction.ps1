. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "clean-room-rehearsal")
if ($result.status -ne "passed") { throw "Clean-room rehearsal did not pass." }
Assert-True $result.validation.no_worker_execution "no_worker_execution"
Assert-True $result.validation.no_workunit_apply "no_workunit_apply"
Assert-True $result.validation.no_queue_apply "no_queue_apply"
Assert-True $result.validation.no_host_mutation "no_host_mutation"
Assert-FileExists ".agent/tmp/portable-package/clean-room-rehearsal-report.json"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-clean-room-portable-extraction"
