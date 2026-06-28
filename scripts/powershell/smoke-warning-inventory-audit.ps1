. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-warning-inventory.ps1" @(
  "-Command", "audit"
)

if ($result.schema -ne "skybridge.warning_inventory.v1") { throw "Unexpected warning inventory schema." }
$warningIds = @($result.known_warnings | ForEach-Object { [string]$_.warning_id })
if ($warningIds -notcontains "vite_chunk_size_warning") { throw "Missing Vite chunk-size warning inventory entry." }
if ($warningIds -notcontains "github_actions_node20_deprecation_annotation") { throw "Missing GitHub Actions Node.js 20 deprecation inventory entry." }
if ($result.vite_chunk_warning_status -ne "non_failing_tracked_not_suppressed") { throw "Unexpected Vite warning status." }
if ($result.github_actions_node20_deprecation_status -ne "non_failing_tracked_not_suppressed") { throw "Unexpected GitHub Actions warning status." }
Assert-True $result.remediation_required "remediation_required"
Assert-False $result.warnings_suppressed "warnings_suppressed"
Assert-False $result.workflow_changed "workflow_changed"
Assert-False $result.build_config_changed "build_config_changed"
Assert-False $result.deploy_config_changed "deploy_config_changed"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "warning-inventory-audit"
