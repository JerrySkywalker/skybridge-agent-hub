$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\desktop\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("desktop-manual-task-chat-card", "Manual Task Chat", "Add to queue", "Run next mock", "Clear completed", "Result preview", "Hermes live provider disabled", "No enabled worker/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing desktop manual task panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in desktop manual task panel." }
Write-Host "[smoke-desktop-manual-task-chat-panel] ok"
