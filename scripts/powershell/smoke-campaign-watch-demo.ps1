$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Once -Json | ConvertFrom-Json
if (-not $json.ok -or $json.mode -ne "demo") { throw "Expected demo watch JSON." }
if ($json.frame -notmatch "Queue") { throw "Expected queue section." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-demo"; token_printed = $false } | ConvertTo-Json -Compress
