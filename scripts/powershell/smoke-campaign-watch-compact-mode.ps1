$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Layout Compact -Frames 1 -MaxFrames 1 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch compact mode smoke failed." }
$text = $raw -join "`n"
if ($text -notmatch "Current\s+super-190") { throw "Expected compact current line." }
if ($text -notmatch "Previous\s+super-189") { throw "Expected compact previous line." }
if ($text -match "Debug Fusion") { throw "Compact output should not include debug block." }
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-compact-mode"; token_printed = $false } | ConvertTo-Json -Compress
