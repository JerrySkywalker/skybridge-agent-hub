. "$PSScriptRoot\smoke-productization-common.ps1"
$analysis = Invoke-JsonScript "skybridge-stop-hook-diagnostics.ps1" @("-Command", "analyze-timeout")
Assert-TokenPrintedFalse $analysis
Assert-False $analysis.raw_logs_persisted "raw_logs_persisted"
Assert-False $analysis.kills_arbitrary_processes "kills_arbitrary_processes"
if ($analysis.likely_causes -notcontains "long-running post-run hook") { throw "Missing expected likely cause." }
Complete-Smoke "stop-hook-diagnostics-timeout"
