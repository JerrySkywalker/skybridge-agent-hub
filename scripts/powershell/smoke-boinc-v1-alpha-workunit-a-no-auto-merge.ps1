$ErrorActionPreference = "Stop"
$path = Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1"
$text = Get-Content -Raw -LiteralPath $path
if ($text -match "gh\s+pr\s+merge|enable_auto_merge|auto-merge\s+enabled") { throw "auto-merge path detected" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-a-no-auto-merge"; token_printed = $false } | ConvertTo-Json -Compress
