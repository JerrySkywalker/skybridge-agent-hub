$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command start-all -DryRun -MaxRuntimeMinutes 60 -Json | ConvertFrom-Json
if ($json.mode -ne "dry-run") { throw "Expected dry-run mode." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-start-all-dry-run"; token_printed = $false } | ConvertTo-Json -Compress
