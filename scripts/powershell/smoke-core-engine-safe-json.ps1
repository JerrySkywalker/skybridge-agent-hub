$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.Core.psm1") -Force
Set-SkybridgeDeterministicTimestamp "2026-06-12T00:00:00.0000000Z"
$path = ".agent/tmp/core-engine/smoke-safe-json.json"
Write-SkybridgeSafeJson -Path $path -Value ([pscustomobject]@{ schema = "skybridge.core_engine_smoke.v1"; timestamp = Get-SkybridgeTimestamp }) | Out-Null
$read = Read-SkybridgeSafeJson -Path $path
if ($read.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-safe-json"; path = $path; token_printed = $false } | ConvertTo-Json -Compress
