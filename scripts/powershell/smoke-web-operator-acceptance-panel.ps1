. "$PSScriptRoot\smoke-productization-common.ps1"
$text = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps/web/src/main.tsx")
foreach ($needle in @("web-operator-acceptance-panel", "Operator Acceptance", "Clean-room rehearsal status", "Artifact integrity status", "Fixture soak status", "Next safe action", "Worker execute disabled")) {
  if ($text -notlike "*$needle*") { throw "Missing web operator acceptance marker: $needle" }
}
Complete-Smoke "smoke-web-operator-acceptance-panel"
