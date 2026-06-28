. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-actions-node-runtime-hygiene.ps1" @(
  "-Command", "audit"
)

Assert-False $result.warning_suppressed "warning_suppressed"
Assert-False $result.ci_threshold_changed "ci_threshold_changed"
Assert-False $result.build_config_changed "build_config_changed"
Assert-False $result.deploy_config_changed "deploy_config_changed"
Assert-False $result.dockerfile_changed "dockerfile_changed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "actions-node-runtime-hygiene-no-suppression"
