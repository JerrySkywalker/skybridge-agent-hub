. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/generated-goals/smoke-no-confirm-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-local-goal-generator.ps1" @("-Command", "generate-one", "-Fixture", "-OutputDir", $outputDir)
$goalPath = Join-Path $RepoRoot $result.generated_goal_path_safe
if (Test-Path -LiteralPath $goalPath) { throw "Generate-one without confirmation wrote markdown." }
if (-not (@($result.blockers) -contains "missing_exact_confirmation")) { throw "Missing confirmation blocker not reported." }
Assert-False $result.proposed_goal_written "proposed_goal_written"
Assert-False $result.codex_generation_called "codex_generation_called"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "local-goal-generator-reject-no-confirm"
