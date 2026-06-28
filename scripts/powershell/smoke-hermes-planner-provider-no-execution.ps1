. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-hermes-planner-provider.ps1" @(
  "-Command", "fixture-plan",
  "-OutputDir", ".agent/tmp/hermes-planner-provider/smoke-no-execution-$([guid]::NewGuid().ToString('N'))"
)

Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.branch_created "branch_created"
Assert-False $result.pr_created "pr_created"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.deploy_triggered "deploy_triggered"
Assert-False $result.raw_prompt_persisted "raw_prompt_persisted"
Assert-False $result.raw_response_persisted "raw_response_persisted"
Assert-False $result.raw_stdout_persisted "raw_stdout_persisted"
Assert-False $result.raw_stderr_persisted "raw_stderr_persisted"
Assert-False $result.secrets_persisted "secrets_persisted"
Assert-TokenPrintedFalse $result

Complete-Smoke "hermes-planner-provider-no-execution"
