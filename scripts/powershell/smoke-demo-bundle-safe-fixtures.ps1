. "$PSScriptRoot\smoke-productization-common.ps1"
foreach ($fixture in @(
  "fixtures/demo/local-session-demo.fixture.json",
  "fixtures/demo/operator-walkthrough.fixture.json",
  "fixtures/demo/product-readiness-demo.fixture.json"
)) {
  Assert-FileExists $fixture
  $text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $fixture)
  Assert-NoUnsafeText $text
  $json = $text | ConvertFrom-Json
  Assert-TokenPrintedFalse $json
}
Complete-Smoke "demo-bundle-safe-fixtures"
