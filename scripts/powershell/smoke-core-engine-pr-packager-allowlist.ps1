$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.PrPackager.psm1") -Force
Assert-SkybridgeAllowedPrPaths @("README.md", "docs/example.md") | Out-Null
if (Test-SkybridgeAllowedPrPath "src/secret.ts") { throw "disallowed path accepted" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-pr-packager-allowlist"; token_printed = $false } | ConvertTo-Json -Compress
