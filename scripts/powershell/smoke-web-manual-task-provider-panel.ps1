$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$path = Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\web\src\main.tsx"
$text = Get-Content -Raw -LiteralPath $path
foreach ($needle in @("web-manual-task-chat-panel", "Provider selector", "mock", "skybridge_server_hermes", "hermes_deepseek", "Run next SkyBridge Hermes", "Run next Hermes preview", "Run next Hermes live opt-in disabled", "Hermes local-direct live provider disabled", "hermes_deepseek deprecated preview-only", "server_mediated_llm_inference_enabled", "cloud_hermes_provider_enabled", "result_hash", "duration_ms", "error_summary", "No enabled worker/apply/start/claim controls", "token_printed=false")) {
  if ($text -notlike "*$needle*") { throw "Missing web manual task provider marker: $needle" }
}
if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') { throw "token marker found in web manual task provider panel." }
Write-Host "[smoke-web-manual-task-provider-panel] ok"
