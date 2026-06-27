. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/multi-goal-loop-smoke-preview-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-multi-goal-loop.ps1" @("-Command", "preview-next", "-Fixture", "-OutputDir", $outputDir)
if ($result.schema -ne "skybridge.multi_goal_loop.v1") { throw "Unexpected schema." }
Assert-True $result.preview_only "preview_only"
Assert-False $result.apply_confirmed "apply_confirmed"
if ([string]$result.next_step_id -ne "safe-local-smoke-step-353-001") { throw "Preview selected wrong step." }
if ([int]$result.task_created_count -ne 0) { throw "Preview created a task." }
if ([int]$result.task_claimed_count -ne 0) { throw "Preview claimed a task." }
if ([int]$result.execution_completed_count -ne 0) { throw "Preview completed execution." }
if (Test-Path -LiteralPath (Join-Path $RepoRoot "$outputDir/fixture-state.json")) { throw "Preview mutated fixture state." }
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "multi-goal-loop-preview"
