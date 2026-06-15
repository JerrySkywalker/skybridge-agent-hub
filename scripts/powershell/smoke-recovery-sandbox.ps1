. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-recovery-sandbox.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-False $report.host_mutation_allowed "host_mutation_allowed"
Assert-True $report.cleanup_hardening.cleanup_preview_only "cleanup_preview_only"
Complete-Smoke "recovery-sandbox"
