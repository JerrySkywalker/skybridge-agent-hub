. "$PSScriptRoot\smoke-productization-common.ps1"
$path = Join-Path $RepoRoot "apps/web/src/main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("product-readiness", "ProductReadinessPage", "Product Readiness", "execution_enabled=false", "Packaging preview", "Windows launcher preview")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing web dashboard marker: $needle" }
}
Complete-Smoke "product-readiness-dashboard-web"
