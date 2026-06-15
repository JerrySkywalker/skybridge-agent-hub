. "$PSScriptRoot\smoke-productization-common.ps1"
Invoke-JsonScript "skybridge-local-soak.ps1" @("-Command", "report") | Out-Null
$path = Join-Path $RepoRoot ".agent/tmp/local-session/restart-cleanup-rehearsal-report.json"
Assert-FileExists ".agent/tmp/local-session/restart-cleanup-rehearsal-report.json"
$result = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
if ($result.status -ne "passed") { throw "Restart cleanup rehearsal failed." }
Assert-False $result.stale_lock "stale_lock"
Assert-False $result.stale_pid "stale_pid"
Assert-False $result.background_process_left_running "background_process_left_running"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-local-restart-cleanup-rehearsal"
