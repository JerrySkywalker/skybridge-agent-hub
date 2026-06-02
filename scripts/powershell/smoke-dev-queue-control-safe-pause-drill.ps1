$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command safe-pause -Reason "188G smoke safe pause" -Json | ConvertFrom-Json
if (-not $json.ok) { throw "Expected safe-pause dry-run ok." }
if ($json.mode -ne "dry-run") { throw "Expected safe-pause without -Apply to be dry-run." }
if ($json.mutates -ne $false) { throw "Expected safe-pause dry-run to report mutates=false." }
if ($json.would_pause_project -ne $true) { throw "Expected safe-pause to preview project pause." }
if ($json.would_hold_runner -ne $true) { throw "Expected safe-pause to preview runner hold." }
if ($json.would_set_stop_requested -ne $false) { throw "Expected safe-pause to preserve stop_requested=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-safe-pause-drill"; token_printed = $false } | ConvertTo-Json -Compress
