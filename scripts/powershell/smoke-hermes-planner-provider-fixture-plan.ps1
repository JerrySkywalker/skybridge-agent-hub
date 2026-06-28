. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/hermes-planner-provider/smoke-fixture-$([guid]::NewGuid().ToString('N'))"
$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "fixture-plan",
  "-OutputDir", $outputDir,
  "-WriteReport"
)

if ($result.schema -ne "skybridge.hermes_planner_provider.v1") { throw "Unexpected Hermes planner provider schema." }
if ($result.mode -ne "fixture") { throw "Unexpected mode." }
Assert-True $result.fixture_response_used "fixture_response_used"
Assert-True $result.candidate_goal_generated "candidate_goal_generated"
Assert-True $result.candidate_validated "candidate_validated"
if ([string]$result.candidate_goal_hash -notmatch "^[0-9a-f]{64}$") { throw "Candidate hash missing." }
$candidatePath = Join-Path $RepoRoot $result.candidate_goal_path_safe
Assert-FileExists $result.candidate_goal_path_safe
$markdown = Get-Content -Raw -LiteralPath $candidatePath
foreach ($required in @("skybridge.generated_goal_metadata.v1", "human_review_required", "import_allowed", "execution_allowed", "No auto-merge", "No worker loop", "token_printed=false")) {
  if ($markdown -notmatch [regex]::Escape($required)) { throw "Candidate missing $required." }
}
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-False $result.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.secrets_persisted "secrets_persisted"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-fixture-plan"
