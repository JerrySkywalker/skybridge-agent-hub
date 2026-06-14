. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-packaging-preview.ps1" @("-Command", "report")
Assert-True $report.metadata_only "metadata_only"
Assert-False $report.installs_package "installs_package"
Assert-FileExists ".agent/tmp/packaging-preview/desktop-packaging-preview.json"
Complete-Smoke "packaging-preview"
