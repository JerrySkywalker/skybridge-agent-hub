$ErrorActionPreference = "Stop"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-campaign-watch.ps1" -Demo -Frames 1 -MaxFrames 1 -ColorMode Never -NoClear
if ($LASTEXITCODE -ne 0) { throw "watch PR/CI/evidence display smoke failed." }
$text = $raw -join "`n"
foreach ($expected in @("#99", "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/99", "merged", "passed", "recovered", "evidence_repaired")) {
  if ($text -notmatch [regex]::Escape($expected)) { throw "Expected PR/CI/evidence output to contain '$expected'." }
}
[pscustomobject]@{ ok = $true; scenario = "campaign-watch-pr-ci-evidence-display"; token_printed = $false } | ConvertTo-Json -Compress
