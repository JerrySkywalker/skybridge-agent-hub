. "$PSScriptRoot\smoke-productization-common.ps1"

Assert-FileExists "docs/dev/WARNING_INVENTORY.md"
$path = Join-Path $RepoRoot "docs/dev/WARNING_INVENTORY.md"
$text = Get-Content -Raw -LiteralPath $path
Assert-NoUnsafeText $text

foreach ($required in @(
  "Vite chunk-size warning",
  "GitHub Actions Node.js 20 deprecation annotation",
  "not suppressed",
  "No CI threshold changes",
  "No Vite config changes",
  "No GitHub workflow changes",
  "MG366A: Vite Chunk Warning Analysis",
  "MG366B: GitHub Actions Node Runtime Hygiene",
  "MG366C: Hermes Planner Provider Pilot",
  "token_printed=false"
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "WARNING_INVENTORY.md missing required text: $required"
  }
}

Complete-Smoke "warning-inventory-doc-present"
