$ErrorActionPreference = "Stop"

$serverText = Get-Content -Raw -LiteralPath (Join-Path (Resolve-Path "$PSScriptRoot\..\..") "apps\server\src\index.ts")
foreach ($forbidden in @("HERMES_DEEPSEEK", "deepseek-chat", ".agent/local/hermes-deepseek.local.json")) {
  if ($serverText -clike "*$forbidden*") { throw "Server must not contain direct DeepSeek contract marker: $forbidden" }
}
foreach ($required in @("/v1/capabilities", "/v1/responses", "HERMES_API_BASE", "HERMES_API_KEY", "skybridge_server_hermes")) {
  if ($serverText -notlike "*$required*") { throw "Missing server Hermes contract marker: $required" }
}
Write-Host "[smoke-manual-task-server-hermes-no-direct-deepseek] ok"
