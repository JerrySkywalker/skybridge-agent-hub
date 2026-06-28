. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-cloud-state" "cloud"

if ($result.state.mode -ne "cloud") { throw "Operator TUI state must use cloud mode." }
Assert-False $result.report.fixture_used "fixture_used"
Assert-False $result.report.local_state_loaded "local_state_loaded"
Assert-True $result.report.cloud_state_loaded "cloud_state_loaded"
Assert-True $result.state.cloud_state_loaded "state.cloud_state_loaded"
Assert-True $result.state.cloud.health_ok "state.cloud.health_ok"
Assert-True $result.state.cloud.version_ok "state.cloud.version_ok"
Assert-True $result.state.cloud.parity_ok "state.cloud.parity_ok"
if ([string]::IsNullOrWhiteSpace([string]$result.state.cloud.commit_sha)) { throw "Cloud commit_sha was not loaded." }
if ([string]::IsNullOrWhiteSpace([string]$result.state.cloud.image_ref)) { throw "Cloud image_ref was not loaded." }
if ([string]::IsNullOrWhiteSpace([string]$result.state.cloud.image_tag)) { throw "Cloud image_tag was not loaded." }
if (@($result.state.cloud.missing_routes).Count -ne 0) { throw "Cloud parity reported missing routes." }

Complete-Smoke "operator-tui-cloud-state"
