. "$PSScriptRoot\smoke-productization-common.ps1"

$checklist = "docs/release/MANAGED_DEV_E2E_FREEZE_CHECKLIST.md"
Assert-FileExists $checklist
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $checklist)

foreach ($required in @(
  "Tool Provider Inventory",
  "Single Goal Loop",
  "Static Multi-Step Campaign",
  "Local Codex Goal Markdown Generator",
  "Goal Append Review/Import",
  "Bounded Goal Budget Loop",
  "Managed Development PR Pilot",
  "controller-native Git/GH",
  "Campaign-Driven Managed Dev E2E",
  "cloud parity ok",
  "token_printed=false"
)) {
  if ($text -notmatch [regex]::Escape($required)) { throw "Freeze checklist missing: $required" }
}

Assert-NoUnsafeText $text
Complete-Smoke "managed-dev-e2e-freeze-checklist"
