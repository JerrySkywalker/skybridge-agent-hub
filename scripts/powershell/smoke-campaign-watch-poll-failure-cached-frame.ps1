$ErrorActionPreference = "Stop"
$old = $env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL
try {
  $env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL = "1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 2 -MaxFrames 2 -PollIntervalSeconds 1 -RenderIntervalMilliseconds 50 -ColorMode Never -NoClear
  if ($LASTEXITCODE -ne 0) { throw "watch cached failure frame failed." }
  $text = $raw -join "`n"
  if ($text -notmatch "WARNING") { throw "Expected warning after simulated poll failure." }
  if ($text -notmatch "Queue") { throw "Expected cached queue frame after poll failure." }
} finally {
  $env:SKYBRIDGE_WATCH_TEST_FAIL_AFTER_FIRST_POLL = $old
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-poll-failure-cached-frame"; token_printed = $false } | ConvertTo-Json -Compress
