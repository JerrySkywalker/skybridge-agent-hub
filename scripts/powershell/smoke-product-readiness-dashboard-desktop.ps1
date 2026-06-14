. "$PSScriptRoot\smoke-productization-common.ps1"
$path = Join-Path $RepoRoot "apps/desktop/src/main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("ProductReadinessCard", "Product Readiness", "launch profile", "Packaging preview", "Windows launcher preview", "EXECUTION DISABLED")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing desktop dashboard marker: $needle" }
}
Complete-Smoke "product-readiness-dashboard-desktop"
