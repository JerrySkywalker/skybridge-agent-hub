. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "status")
if ($result.result.status -ne "ready") { throw "Expected launcher ready." }
Assert-False $result.result.execution_enabled "execution_enabled"
Assert-False $result.result.queue_apply_enabled "queue_apply_enabled"
Assert-TokenPrintedFalse $result
Complete-Smoke "repo-local-launcher-status"
