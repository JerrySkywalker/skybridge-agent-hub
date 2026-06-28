. "$PSScriptRoot\smoke-productization-common.ps1"

Assert-FileExists "docs/release/STAGE_S1_1_CLOSE.md"
Assert-FileExists "scripts/powershell/skybridge-stage-s1-1-close.ps1"

$doc = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs/release/STAGE_S1_1_CLOSE.md")
foreach ($needle in @(
  "Stage S1.1",
  "Managed Dev E2E",
  "Hermes Planner",
  "Vite chunk-size warning remains non-failing",
  "GitHub Actions Node.js 20 deprecation annotation",
  "MG367C Hermes Candidate Review/Append Gate",
  "token_printed=false"
)) {
  if ($doc -notmatch [regex]::Escape($needle)) { throw "Stage close doc missing expected text: $needle" }
}

Assert-NoUnsafeText $doc
Complete-Smoke "stage-s1-1-close-doc-present"
