$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-manual-task-chat-panel", "Provider selector", "mock", "hermes_deepseek", "Run next Hermes preview", "Run next Hermes live opt-in disabled", "Hermes live provider disabled", "Hermes DeepSeek preview no-network", "result_hash", "duration_ms", "error_summary", "No enabled worker/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web manual task provider marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in web manual task provider panel." }
Write-Host "[smoke-web-manual-task-provider-panel] ok"
