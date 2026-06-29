. "$PSScriptRoot\operator-tui-smoke-common.ps1"

$result = Invoke-OperatorTuiSnapshot "smoke-snapshot" "fixture"

if ($result.report.mode -ne "fixture") { throw "Operator TUI report mode must be fixture." }
foreach ($text in @(
  "SkyBridge Operator Console - MG368B Read-only Snapshot",
  "READ ONLY",
  "mode=fixture",
  "no mutation",
  "token_printed=false"
)) {
  if ($result.snapshot_text -notmatch [regex]::Escape($text)) { throw "Snapshot missing text: $text" }
}

Complete-Smoke "operator-tui-snapshot"
