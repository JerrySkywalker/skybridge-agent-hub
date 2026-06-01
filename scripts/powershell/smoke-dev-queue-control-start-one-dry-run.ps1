$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command start-one -DryRun -MaxRuntimeMinutes 60 -Json | ConvertFrom-Json
if ($json.mode -ne "dry-run") { throw "Expected dry-run mode." }
if ($json.runner_status -notin @("held", "completed", "idle")) { throw "Unexpected runner status: $($json.runner_status)" }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-start-one-dry-run"; token_printed = $false } | ConvertTo-Json -Compress
