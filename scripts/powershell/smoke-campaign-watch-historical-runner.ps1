$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Layout Debug -Frames 1 -MaxFrames 1 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch historical runner smoke failed." }
$text = $raw -join "`n"
if ($text -notmatch "historical_warning") { throw "Expected historical_warning classification." }
if ($text -notmatch "not a current blocker") { throw "Expected old runner failure to be shown as historical." }
if ($text -notmatch "runner.failed") { throw "Expected historical runner failure event." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-historical-runner"; token_printed = $false } | ConvertTo-Json -Compress
