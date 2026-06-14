. "$PSScriptRoot\smoke-productization-common.ps1"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/web/src/main.tsx")
foreach ($needle in @("FirstRunWizardPage", "skybridge.first_run_wizard.v1", "first-run", "Backup/restore preview", "no execute controls")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing web wizard marker: $needle" }
}
Complete-Smoke "first-run-wizard-web"
