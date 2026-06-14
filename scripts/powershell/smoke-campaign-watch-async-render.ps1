$ErrorActionPreference = "Stop"
$oldDelay = $env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS
try {
  $env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS = "2000"
  $started = Get-Date
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 1 -MaxFrames 4 -PollIntervalSeconds 5 -RenderIntervalMilliseconds 50 -ColorMode Never -NoClear
  $elapsed = ((Get-Date) - $started).TotalMilliseconds
  if ($LASTEXITCODE -ne 0) { throw "watch async render smoke failed." }
  $text = $raw -join "`n"
  if ($elapsed -ge 1800) { throw "Render loop blocked on slow poll; elapsed=${elapsed}ms." }
  if ($text -notmatch "Polling remote state") { throw "Expected cached placeholder while poll is in flight." }
  if (($text.ToCharArray() | Where-Object { $_ -in @([char]"|", [char]"/", [char]"-", [char]"\") }).Count -lt 2) { throw "Expected multiple spinner frames during slow poll." }
} finally {
  if ($null -eq $oldDelay) { Remove-Item Env:\SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS -ErrorAction SilentlyContinue }
  else { $env:SKYBRIDGE_WATCH_TEST_POLL_DELAY_MS = $oldDelay }
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-async-render"; token_printed = $false } | ConvertTo-Json -Compress
