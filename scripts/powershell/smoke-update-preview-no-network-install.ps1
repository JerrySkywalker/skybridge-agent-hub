. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-update-preview.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/upgrade-preview/update-preview-report.json"
Assert-False $report.channel.network_update "network_update"
Assert-False $report.channel.binary_install "binary_install"
Assert-False $report.channel.github_release_creation "github_release_creation"
Assert-TokenPrintedFalse $report
Complete-Smoke "update-preview-no-network-install"
