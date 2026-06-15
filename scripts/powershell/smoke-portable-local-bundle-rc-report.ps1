. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $report
Assert-FileExists ".agent/tmp/portable-bundle/portable-local-bundle-rc-report.json"
$rc = Get-Content -Raw (Join-Path $RepoRoot ".agent/tmp/portable-bundle/portable-local-bundle-rc-report.json") | ConvertFrom-Json
Assert-TokenPrintedFalse $rc
if ($rc.rc_version -ne "v1.4.0-portable-local-bundle-rc") { throw "Unexpected rc_version." }
Complete-Smoke "portable-local-bundle-rc-report"
