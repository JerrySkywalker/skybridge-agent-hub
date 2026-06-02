$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command emergency-stop -Reason "188G smoke emergency stop" -Json | ConvertFrom-Json
if (-not $json.ok) { throw "Expected emergency-stop dry-run ok." }
if ($json.mode -ne "dry-run") { throw "Expected emergency-stop without -Apply to be dry-run." }
if ($json.mutates -ne $false) { throw "Expected emergency-stop dry-run to report mutates=false." }
if ($json.would_stop_project -ne $true) { throw "Expected emergency-stop to preview project stop." }
if ($json.would_set_stop_requested -ne $true) { throw "Expected emergency-stop to preview stop_requested=true." }
if ($json.instructions -notmatch "Ctrl\+C") { throw "Expected Ctrl+C instruction." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-emergency-stop-drill"; token_printed = $false } | ConvertTo-Json -Compress
