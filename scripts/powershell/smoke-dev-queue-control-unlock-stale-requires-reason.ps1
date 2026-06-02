$ErrorActionPreference = "Stop"
$output = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command unlock-stale-runner -Json 2>&1
if ($LASTEXITCODE -eq 0) { throw "Expected unlock-stale-runner without -Reason to fail." }
if (($output -join "`n") -notmatch "requires -Reason") { throw "Expected missing reason error." }
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command unlock-stale-runner -Reason "188G smoke unlock preview" -Json | ConvertFrom-Json
if ($json.mode -ne "dry-run") { throw "Expected unlock without -Apply to be dry-run." }
if ($json.requires_apply -ne $true) { throw "Expected unlock dry-run to report requires_apply=true." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-unlock-stale-requires-reason"; token_printed = $false } | ConvertTo-Json -Compress
