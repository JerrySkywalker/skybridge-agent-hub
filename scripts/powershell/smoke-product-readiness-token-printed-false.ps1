. "$PSScriptRoot\smoke-productization-common.ps1"
$readiness = Invoke-JsonScript "skybridge-diagnostics.ps1" @("-Command", "product-readiness")
Assert-TokenPrintedFalse $readiness
$web = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/web/src/main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
if ($web -match "token_printed=true" -or $desktop -match "token_printed=true") { throw "token_printed=true marker found." }
Complete-Smoke "product-readiness-token-printed-false"
