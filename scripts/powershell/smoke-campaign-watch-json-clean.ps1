$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Once -Json
if ($LASTEXITCODE -ne 0) { throw "watch json failed." }
if (($raw -join "`n") -match "\x1b\[") { throw "JSON output must not contain ANSI escapes." }
$json = $raw | ConvertFrom-Json
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-json-clean"; token_printed = $false } | ConvertTo-Json -Compress
