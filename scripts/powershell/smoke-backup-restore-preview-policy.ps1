. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-backup-restore-preview.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/upgrade-preview/backup-restore-preview.json"
Assert-False $report.backup_policy.writes_external_locations "writes_external_locations"
Assert-True ($report.backup_policy.exclude -contains "tokens") "tokens excluded"
Complete-Smoke "backup-restore-preview-policy"
