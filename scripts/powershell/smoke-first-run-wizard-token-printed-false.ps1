. "$PSScriptRoot\smoke-productization-common.ps1"
$web = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/web/src/main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
if ($web -match "token_printed=true" -or $desktop -match "token_printed=true") { throw "token_printed=true found." }
Complete-Smoke "first-run-wizard-token-printed-false"
