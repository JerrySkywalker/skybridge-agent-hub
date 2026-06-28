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
