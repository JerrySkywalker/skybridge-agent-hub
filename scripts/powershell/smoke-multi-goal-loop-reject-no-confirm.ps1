. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/multi-goal-loop-smoke-no-confirm-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "apply-next", "-Fixture", "-OutputDir", $outputDir)
if (@($result.blockers) -notcontains "missing_exact_confirmation") { throw "Missing confirmation was not rejected." }
Assert-False $result.apply_confirmed "apply_confirmed"
if ([int]$result.task_created_count -ne 0 -or [int]$result.task_claimed_count -ne 0 -or [int]$result.execution_completed_count -ne 0) { throw "Reject path mutated task state." }
if (Test-Path -LiteralPath (Join-Path $RepoRoot "$outputDir/fixture-state.json")) { throw "Reject path wrote fixture state." }
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "multi-goal-loop-reject-no-confirm"
