. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-True $report.manifest.forbidden_paths_absent "forbidden_paths_absent"
Assert-False $report.manifest.registry_write_allowed "registry_write_allowed"
Assert-False $report.manifest.service_install_allowed "service_install_allowed"
Complete-Smoke "installer-manifest"
