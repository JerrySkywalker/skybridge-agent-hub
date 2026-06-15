. "$PSScriptRoot\smoke-productization-common.ps1"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/desktop/src/main.tsx")
foreach ($needle in @("desktop-operator-acceptance-panel", "Operator Acceptance", "Clean-room rehearsal status", "Artifact integrity status", "Fixture soak status", "Next safe action", "Worker execute disabled")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop operator acceptance marker: $needle" }
}
Complete-Smoke "smoke-desktop-operator-acceptance-panel"
