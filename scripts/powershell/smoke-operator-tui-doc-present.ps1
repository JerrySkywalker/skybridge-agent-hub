. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-doc-present"

Assert-FileExists "apps/operator-tui/Cargo.toml"
Assert-FileExists "docs/operator/RATATUI_OPERATOR_CONSOLE.md"

$docPath = Join-Path $RepoRoot "docs/operator/RATATUI_OPERATOR_CONSOLE.md"
$doc = Get-Content -Raw -LiteralPath $docPath
Assert-NoUnsafeText $doc
foreach ($required in @(
  "MG368A",
  "fixture/read-only",
  "MG368B",
  "--local-cloud",
  "local_state_loaded",
  "cloud_state_loaded",
  "local_cloud_parity_checked",
  "candidate-flow",
  "I_UNDERSTAND_REVIEW_CANDIDATE_FOR_APPEND_ONLY_NO_EXECUTION",
  "I_UNDERSTAND_APPEND_REVIEWED_CANDIDATE_TO_CAMPAIGN_NO_EXECUTION",
  "I_UNDERSTAND_START_ONE_GOAL_SINGLE_STEP_ONLY_NO_QUEUE_LOOP",
  "I_UNDERSTAND_SAFE_PAUSE_SINGLE_STEP_PIPELINE_WITH_REASON",
  "I_UNDERSTAND_ABORT_TERMINATE_PREVIEW_OR_FIXTURE_ONLY_NO_PROCESS_KILL",
  "append-only/no-execution",
  "one-action-only",
  "no start_one_apply",
  "no start_queue_apply",
  "no worker loop",
  "token_printed=false",
  "MG368C",
  "MG368D",
  "MG369"
)) {
  if ($doc -notmatch [regex]::Escape($required)) { throw "Operator TUI doc missing: $required" }
}

if ($result.report.fixture_used -ne $true) { throw "Doc smoke snapshot must use fixture state." }

Complete-Smoke "operator-tui-doc-present"
