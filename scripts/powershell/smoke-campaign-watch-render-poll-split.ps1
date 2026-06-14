$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 3 -MaxFrames 3 -PollIntervalSeconds 5 -RenderIntervalMilliseconds 50 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch render/poll split failed." }
$text = $raw -join "`n"
if ($text -notmatch "refreshed=") { throw "Expected refreshed age in watch frame." }
if (($text.ToCharArray() | Where-Object { $_ -in @([char]"|", [char]"/", [char]"-", [char]"\") }).Count -lt 2) { throw "Expected multiple spinner frames." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-render-poll-split"; token_printed = $false } | ConvertTo-Json -Compress
