$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command emergency-stop -Reason smoke -Json | ConvertFrom-Json
if ($json.mode -ne "dry-run" -or $json.would_stop_project -ne $true) { throw "Expected dry-run emergency stop preview." }
if ($json.instructions -notmatch "Ctrl\\+C") { throw "Expected Ctrl+C instruction." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-emergency-stop-requires-apply"; token_printed = $false } | ConvertTo-Json -Compress
