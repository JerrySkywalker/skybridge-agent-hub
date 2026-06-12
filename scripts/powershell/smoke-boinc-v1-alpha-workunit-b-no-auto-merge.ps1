$ErrorActionPreference = "Stop"
$script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1")
if ($script -match '(?i)enable-auto-merge|--auto-merge') { throw "Workunit B must not enable auto-merge" }
if ($script -notlike "*no auto-merge*") { throw "Workunit B PR body must state no auto-merge" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-no-auto-merge"; token_printed = $false } | ConvertTo-Json -Compress
