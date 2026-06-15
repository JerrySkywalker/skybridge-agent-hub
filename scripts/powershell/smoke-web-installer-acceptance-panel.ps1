$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-release-workflow-guard-panel", "web-installer-candidate-panel", "web-sandbox-installed-runtime-panel", "web-install-soak-panel", "web-recovery-sandbox-panel", "web-operator-acceptance-v3-panel", "Create Release disabled", "Real install disabled", "Queue apply disabled", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web installer acceptance marker: $needle" }
}
[pscustomobject]@{ ok = $true; scenario = "web-installer-acceptance-panel"; token_printed = $false } | ConvertTo-Json -Compress
