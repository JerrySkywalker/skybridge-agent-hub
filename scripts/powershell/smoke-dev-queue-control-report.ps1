$ErrorActionPreference = "Stop"
$json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
if (-not $json.ok) { throw "Expected report ok." }
if ($json.token_printed -ne $false) { throw "Expected token_printed=false." }
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-report"; token_printed = $false } | ConvertTo-Json -Compress
