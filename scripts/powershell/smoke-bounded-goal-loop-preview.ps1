. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/bounded-goal-loop/smoke-preview-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "preview",
  "-Fixture",
  "-Scenario", "generate",
  "-OutputDir", $outputDir
)
Assert-True $result.preview_only "preview_only"
Assert-False $result.action_performed "action_performed"
Assert-False $result.goal_generated "goal_generated"
Assert-False $result.goal_appended "goal_appended"
Assert-False $result.task_created "task_created"
if ([int]$result.action_count -ne 0) { throw "Preview selected mutation count." }
$generatedPath = Join-Path (Join-Path $RepoRoot $outputDir) "generated/bounded-loop-generated-goal-356-fixture.md"
if (Test-Path -LiteralPath $generatedPath) { throw "Preview created generated markdown." }
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-preview"
