. "$PSScriptRoot\smoke-productization-common.ps1"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
foreach ($needle in @("FirstRunWizardCard", "skybridge.first_run_wizard.v1", "Backup/restore preview", "Disabled controls")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing desktop wizard marker: $needle" }
}
Complete-Smoke "first-run-wizard-desktop"
