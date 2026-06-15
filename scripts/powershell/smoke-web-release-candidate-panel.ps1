[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("InstallerPromotionRcPanel", "Release Artifact Manifest", "Update Channel Manifest", "Host Mutation Gate", "Operator Acceptance v4", "Install disabled", "Worker execute disabled")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing web panel marker: $needle" }
}
Write-Host "[smoke-web-release-candidate-panel] ok"
