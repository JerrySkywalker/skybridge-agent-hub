[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
$path = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("DesktopReleaseCandidatePanel", "Installer promotion", "Release artifact", "Host mutation disabled", "Long soak", "Acceptance v4", "Install disabled")) {
  if ($text -notmatch [regex]::Escape($needle)) { throw "Missing desktop panel marker: $needle" }
}
Write-Host "[smoke-desktop-release-candidate-panel] ok"
