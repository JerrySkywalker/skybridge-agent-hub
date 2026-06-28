. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/hermes-planner-provider/smoke-validate-$([guid]::NewGuid().ToString('N'))"
$fixture = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "fixture-plan",
  "-OutputDir", $outputDir
)
$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "validate-candidate",
  "-OutputDir", $outputDir,
  "-CandidatePath", $fixture.candidate_goal_path_safe,
  "-ExpectedHash", $fixture.candidate_goal_hash
)

Assert-True $result.candidate_validated "candidate_validated"
if ($result.candidate_goal_hash -ne $fixture.candidate_goal_hash) { throw "Candidate hash changed." }
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-validate-candidate"
