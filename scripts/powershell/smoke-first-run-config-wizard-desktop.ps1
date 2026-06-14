. "$PSScriptRoot\smoke-productization-common.ps1"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
foreach ($needle in @("Config wizard preview", "skybridge.local_config.v1", "skybridge.local_config_validation.v1", "v1.1.0-local-productization-rc")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing desktop config wizard marker: $needle" }
}
Complete-Smoke "first-run-config-wizard-desktop"
