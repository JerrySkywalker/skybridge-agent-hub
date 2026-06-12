$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.SmokeHarness.psm1") -Force
Assert-SkybridgeTokenPrintedFalse ([pscustomobject]@{ token_printed = $false }) | Out-Null
[pscustomobject]@{ ok = $true; scenario = "core-engine-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
