$ErrorActionPreference = "Stop"
$output = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Once -ColorMode Never -NoClear
if (($output -join "`n") -match "\x1b\[") { throw "ColorMode Never must not emit ANSI escapes." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-color-never"; token_printed = $false } | ConvertTo-Json -Compress
