$ErrorActionPreference = "Stop"
$output = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Once -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch once failed." }
$text = $output -join "`n"
if ($text -notmatch "SkyBridge Dev Queue Watch") { throw "Expected watch header." }
if ($text -notmatch "Current Step") { throw "Expected current step section." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-once"; token_printed = $false } | ConvertTo-Json -Compress
