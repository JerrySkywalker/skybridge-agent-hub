. "$PSScriptRoot\smoke-productization-common.ps1"
$web = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/web/src/main.tsx")
$desktop = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
foreach ($needle in @("Start disabled", "Apply disabled", "Claim disabled")) {
  if ($web -notmatch [regex]::Escape($needle)) { throw "Missing web disabled wizard control: $needle" }
  if ($desktop -notmatch [regex]::Escape($needle)) { throw "Missing desktop disabled wizard control: $needle" }
}
if ($web -match "FirstRunWizardPage[\\s\\S]*Start enabled" -or $desktop -match "FirstRunWizardCard[\\s\\S]*Start enabled") {
  throw "Enabled wizard start control found."
}
Complete-Smoke "first-run-wizard-no-enabled-execution"
