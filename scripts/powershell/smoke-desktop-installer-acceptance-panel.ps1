$ErrorActionPreference = "Stop"
$path = Join-Path (Split-Path -Parent $PSScriptRoot) "..\apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-installer-candidate-card", "desktop-sandbox-installed-runtime-card", "desktop-recovery-card", "desktop-acceptance-v3-card", "Installer Candidate", "Sandbox-installed Runtime", "Recovery Sandbox", "Operator Acceptance v3", "Worker execute disabled", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop installer acceptance marker: $needle" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-installer-acceptance-panel"; token_printed = $false } | ConvertTo-Json -Compress
