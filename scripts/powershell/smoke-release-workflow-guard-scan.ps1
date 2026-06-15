. "$PSScriptRoot\smoke-productization-common.ps1"
$scan = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "scan-workflows")
Assert-TokenPrintedFalse $scan
Assert-True ($scan.workflow_count -gt 0) "workflow_count"
Assert-False $scan.workflow_values_read "workflow_values_read"
Complete-Smoke "release-workflow-guard-scan"
