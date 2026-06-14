. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-windows-launcher-preview.ps1" @("-Command", "shortcut-preview")
Assert-False $report.startup_folder_write "startup_folder_write"
Assert-False $report.powercfg_mutation "powercfg_mutation"
Assert-False $report.sleep_or_standby_mutation "sleep_or_standby_mutation"
Complete-Smoke "windows-launcher-preview-no-startup-write"
