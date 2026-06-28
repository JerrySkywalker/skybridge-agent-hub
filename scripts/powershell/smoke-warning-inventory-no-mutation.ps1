. "$PSScriptRoot\smoke-productization-common.ps1"

$before = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()

$result = Invoke-JsonScript "skybridge-warning-inventory.ps1" @(
  "-Command", "safe-summary"
)

$after = (git -C $RepoRoot status --porcelain=v1 | Out-String).Trim()
if ($before -ne $after) {
  throw "Read-only warning inventory changed git status."
}

Assert-False $result.warnings_suppressed "warnings_suppressed"
Assert-False $result.workflow_changed "workflow_changed"
Assert-False $result.build_config_changed "build_config_changed"
Assert-False $result.deploy_config_changed "deploy_config_changed"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "warning-inventory-no-mutation"
