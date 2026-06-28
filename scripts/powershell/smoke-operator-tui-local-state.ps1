. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-local-state" "local"

if ($result.state.mode -ne "local") { throw "Operator TUI state must use local mode." }
Assert-False $result.report.fixture_used "fixture_used"
Assert-True $result.report.local_state_loaded "local_state_loaded"
Assert-False $result.report.cloud_state_loaded "cloud_state_loaded"
Assert-True $result.state.local_state_loaded "state.local_state_loaded"
if ([string]::IsNullOrWhiteSpace([string]$result.state.repo.branch)) { throw "Local branch was not loaded." }
if ([string]::IsNullOrWhiteSpace([string]$result.state.repo.head)) { throw "Local HEAD was not loaded." }
if ([string]::IsNullOrWhiteSpace([string]$result.state.repo.repository_root)) { throw "Repository root was not loaded." }
if ([string]::IsNullOrWhiteSpace([string]$result.state.repo.package_manager_marker)) { throw "Package manager marker was not loaded." }
if ([string]$result.state.local_state_source -ne "git_read_only") { throw "Unexpected local_state_source: $($result.state.local_state_source)" }

Complete-Smoke "operator-tui-local-state"
