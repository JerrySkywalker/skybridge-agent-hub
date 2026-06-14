. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-windows-launcher-preview.ps1" @("-Command", "report")
Assert-True $report.dry_run "dry_run"
Assert-True $report.preview_only "preview_only"
Assert-False $report.applies_host_changes "applies_host_changes"
Assert-FileExists ".agent/tmp/windows-launcher-preview/windows-launcher-preview.json"
Complete-Smoke "windows-launcher-preview-dry-run"
