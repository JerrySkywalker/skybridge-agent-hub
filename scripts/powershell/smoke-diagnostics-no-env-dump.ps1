. "$PSScriptRoot\smoke-productization-common.ps1"
Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "report") | Out-Null
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot ".agent/tmp/diagnostics/health-report.json")
Assert-NoUnsafeText $text
if ($text -match "(?i)PATH=|USERPROFILE=|APPDATA=|env:") { throw "Environment dump detected." }
Complete-Smoke "diagnostics-no-env-dump"
