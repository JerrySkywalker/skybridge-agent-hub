. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-actions-node-runtime-hygiene.ps1" @(
  "-Command", "audit"
)

Assert-False $result.permissions_expanded "permissions_expanded"
Assert-False $result.triggers_changed "triggers_changed"
Assert-False $result.secrets_changed "secrets_changed"
Assert-False $result.deploy_config_changed "deploy_config_changed"
Assert-False $result.dockerfile_changed "dockerfile_changed"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "actions-node-runtime-hygiene-no-permission-expansion"
