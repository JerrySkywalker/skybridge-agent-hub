$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-manual-task-chat-panel", "Manual Task Chat", "Add to queue", "Run next mock", "Clear completed", "Result preview", "Hermes live provider disabled", "No enabled worker/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web manual task panel marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in web manual task panel." }
Write-Host "[smoke-web-manual-task-chat-panel] ok"
