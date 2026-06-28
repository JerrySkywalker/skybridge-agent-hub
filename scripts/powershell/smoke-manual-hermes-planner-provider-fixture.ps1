. "$PSScriptRoot\smoke-productization-common.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-hermes-planner-provider-test.ps1") `
  -RunFixture `
  -Json `
  -WriteReport `
  -OutputDir ".agent/tmp/hermes-planner-provider/smoke-manual-$([guid]::NewGuid().ToString('N'))"
if ($LASTEXITCODE -ne 0) { throw "manual-hermes-planner-provider-test.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

if ($result.schema -ne "skybridge.hermes_planner_provider_manual_test.v1") { throw "Unexpected manual Hermes planner provider schema." }
Assert-True $result.candidate_validated "candidate_validated"
Assert-False $result.candidate_approved "candidate_approved"
Assert-False $result.candidate_appended "candidate_appended"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.branch_created "branch_created"
Assert-False $result.pr_created "pr_created"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.deploy_triggered "deploy_triggered"
Assert-False $result.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.secrets_persisted "secrets_persisted"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-hermes-planner-provider-fixture"
