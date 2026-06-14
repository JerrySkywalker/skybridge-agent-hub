. "$PSScriptRoot\smoke-productization-common.ps1"
Assert-FileExists "docs/dev/PRODUCT_STATE_LAYOUT.md"
Assert-FileExists "docs/dev/LOCAL_PRODUCTIZATION_OVERVIEW.md"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "docs/dev/PRODUCT_STATE_LAYOUT.md")
foreach ($schema in @("skybridge.product_state_layout.v1", "skybridge.product_profile.v1", "skybridge.local_runtime_paths.v1", "skybridge.local_state_health.v1")) {
  if ($text -notmatch [regex]::Escape($schema)) { throw "Missing schema $schema" }
}
Complete-Smoke "product-state-layout"
