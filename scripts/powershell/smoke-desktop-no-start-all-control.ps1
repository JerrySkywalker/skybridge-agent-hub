$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
$guardCount = ([regex]::Matches($desktop, "start_all_present")).Count
if ($desktop -match "Start All enabled|start-all apply|start_all_enabled") { throw "Desktop exposes Start All control." }
if ($guardCount -lt 1) { throw "Desktop execution guard must model start_all_present=false." }
[pscustomobject]@{ ok = $true; scenario = "desktop-no-start-all-control"; start_all_present = $false; token_printed = $false } | ConvertTo-Json -Compress
