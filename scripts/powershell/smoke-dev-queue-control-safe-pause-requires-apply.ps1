$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command safe-pause -Reason smoke -Json | ConvertFrom-Json
if ($json.mode -ne "dry-run" -or $json.would_pause_project -ne $true) { throw "Expected dry-run safe pause preview." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-safe-pause-requires-apply"; token_printed = $false } | ConvertTo-Json -Compress
