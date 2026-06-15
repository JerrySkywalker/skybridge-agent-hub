. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-install-soak.ps1" @("-Command", "install-upgrade-rollback-soak")
Assert-TokenPrintedFalse $report
Assert-True ($report.cycle_count -ge 1) "cycle_count"
Assert-False $report.background_process_left "background_process_left"
Assert-False $report.host_mutation_allowed "host_mutation_allowed"
Complete-Smoke "install-upgrade-rollback-soak"
