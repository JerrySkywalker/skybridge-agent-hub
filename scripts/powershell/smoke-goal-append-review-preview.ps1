. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/goal-append/smoke-review-preview-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-goal-append.ps1" @("-Command", "review-preview", "-Fixture", "-OutputDir", $outputDir)
Assert-True $result.metadata_valid "metadata_valid"
Assert-True $result.safety_valid "safety_valid"
Assert-False $result.import_performed "import_performed"
Assert-False $result.approval_performed "approval_performed"
Assert-False $result.append_performed "append_performed"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

$candidatePath = Join-Path $RepoRoot $result.candidate_path_safe
$reviewState = Join-Path (Join-Path $RepoRoot $outputDir) "review-state\review-state.json"
$campaignState = Join-Path (Join-Path $RepoRoot $outputDir) "campaign-state.json"
if (Test-Path -LiteralPath $candidatePath) { throw "review-preview wrote candidate file." }
if (Test-Path -LiteralPath $reviewState) { throw "review-preview wrote review state." }
if (Test-Path -LiteralPath $campaignState) { throw "review-preview wrote campaign state." }

Complete-Smoke "goal-append-review-preview"
