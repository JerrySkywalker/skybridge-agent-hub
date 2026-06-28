. "$PSScriptRoot\smoke-productization-common.ps1"

Assert-FileExists "docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md"
Assert-FileExists "scripts/powershell/skybridge-vite-chunk-warning-analysis.ps1"

$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs/dev/VITE_CHUNK_WARNING_ANALYSIS.md")
Assert-NoUnsafeText $text

foreach ($required in @(
  "Vite Chunk Warning Analysis",
  "non-failing, tracked, not suppressed",
  "Do not suppress warnings silently",
  'Do not raise `chunkSizeWarningLimit` in MG366A',
  "MG367A Vite Chunk Remediation",
  "token_printed=false"
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "VITE_CHUNK_WARNING_ANALYSIS.md missing required text: $required"
  }
}

Complete-Smoke "vite-chunk-warning-analysis-doc-present"
