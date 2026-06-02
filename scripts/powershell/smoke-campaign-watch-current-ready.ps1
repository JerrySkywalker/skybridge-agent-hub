$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 1 -MaxFrames 1 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch current ready smoke failed." }
$text = $raw -join "`n"
foreach ($expected in @("super-189-ci-guardian-pr-finalizer-hardening  completed", "super-190-campaign-run-report-evidence-ledger", "READY", "active=0", "stale_leases=0", "Goal 190 ready/current; not executed")) {
  if ($text -notmatch [regex]::Escape($expected)) { throw "Expected watch output to contain '$expected'." }
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-current-ready"; token_printed = $false } | ConvertTo-Json -Compress
