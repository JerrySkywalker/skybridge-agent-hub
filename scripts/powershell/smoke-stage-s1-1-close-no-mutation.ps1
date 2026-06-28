. "$PSScriptRoot\smoke-productization-common.ps1"

$before = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()

$result = Invoke-JsonScript "skybridge-stage-s1-1-close.ps1" @(
  "-Command", "safe-summary"
)

$after = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()
if ($before -ne $after) {
  throw "Stage S1.1 close safe summary changed git status."
}

Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.queue_runner_started "queue_runner_started"
Assert-False $result.task_created "task_created"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_live_called "hermes_live_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "stage-s1-1-close-no-mutation"
