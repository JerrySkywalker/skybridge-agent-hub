$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.PrPackager.psm1") -Force
Assert-SkybridgeAllowedPrPaths -Paths @("docs/boinc-v1-alpha-workunit-a.md") | Out-Null
if (Test-SkybridgeAllowedPrPath "apps/web/src/main.tsx") { throw "code path should not be allowed" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-a-packaging-allowlist"; token_printed = $false } | ConvertTo-Json -Compress
