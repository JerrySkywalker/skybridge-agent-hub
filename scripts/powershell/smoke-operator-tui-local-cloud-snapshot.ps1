. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-local-cloud-snapshot" "local-cloud" ".agent/tmp/operator-tui/local-cloud"

if ($result.state.mode -ne "local-cloud") { throw "Operator TUI state must use local-cloud mode." }
if ($result.report.mode -ne "local-cloud") { throw "Operator TUI report mode must be local-cloud." }
Assert-False $result.report.fixture_used "fixture_used"
Assert-True $result.report.local_state_loaded "local_state_loaded"
Assert-True $result.report.cloud_state_loaded "cloud_state_loaded"
Assert-True $result.report.local_cloud_parity_checked "local_cloud_parity_checked"
Assert-True $result.state.local_state_loaded "state.local_state_loaded"
Assert-True $result.state.cloud_state_loaded "state.cloud_state_loaded"
Assert-True $result.state.cloud.parity_ok "state.cloud.parity_ok"

foreach ($text in @(
  "READ ONLY LOCAL/CLOUD MONITOR",
  "Read-only local/cloud monitor",
  "tracked warning: Vite chunk-size warning non-failing",
  "resolved warning: GitHub Actions Node.js 20 deprecation resolved",
  "single-step gate enabled in MG368D; first real experiment deferred to MG369",
  "token_printed=false"
)) {
  if ($result.snapshot_text -notmatch [regex]::Escape($text)) { throw "Local-cloud snapshot missing text: $text" }
}

Complete-Smoke "operator-tui-local-cloud-snapshot"
