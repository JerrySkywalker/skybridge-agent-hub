. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-fixture"

if ($result.state.mode -ne "fixture") { throw "Operator TUI state must use fixture mode." }
Assert-True $result.report.fixture_used "fixture_used"
Assert-False $result.report.interactive_started "interactive_started"
if ($result.state.hermes_candidate.candidate_approved -ne $false) { throw "Candidate must not be approved." }
if ($result.state.hermes_candidate.candidate_appended -ne $false) { throw "Candidate must not be appended." }

Complete-Smoke "operator-tui-fixture"
