. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-snapshot"

if ($result.report.mode -ne "snapshot") { throw "Operator TUI report mode must be snapshot." }
foreach ($text in @(
  "SkyBridge Operator Console - MG368A Snapshot",
  "READ ONLY",
  "fixture mode",
  "no mutation",
  "token_printed=false"
)) {
  if ($result.snapshot_text -notmatch [regex]::Escape($text)) { throw "Snapshot missing text: $text" }
}

Complete-Smoke "operator-tui-snapshot"
