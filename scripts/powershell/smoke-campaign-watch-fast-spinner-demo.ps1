$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 4 -MaxFrames 4 -PollIntervalSeconds 5 -RenderIntervalMilliseconds 50 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch fast spinner demo failed." }
$text = $raw -join "`n"
foreach ($frame in @("|", "/", "-", "\")) {
  if (-not $text.Contains($frame)) { throw "Expected spinner frame $frame." }
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-fast-spinner-demo"; token_printed = $false } | ConvertTo-Json -Compress
