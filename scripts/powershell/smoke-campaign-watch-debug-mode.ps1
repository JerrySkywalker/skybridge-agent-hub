$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Layout Debug -Frames 1 -MaxFrames 1 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch debug mode smoke failed." }
$text = $raw -join "`n"
foreach ($expected in @("Debug Fusion", "campaign_current:", "runner_current:", "runner_class:", "historical_warning", "active_tasks:        0", "stale_leases:        0")) {
  if ($text -notmatch [regex]::Escape($expected)) { throw "Expected debug output to contain '$expected'." }
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-debug-mode"; token_printed = $false } | ConvertTo-Json -Compress
