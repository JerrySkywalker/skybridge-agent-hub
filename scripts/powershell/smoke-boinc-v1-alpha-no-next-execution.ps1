$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-completion-readiness -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.no_next_execution_authorized -ne $true) { throw "next execution is authorized unexpectedly" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-no-next-execution"; token_printed = $false } | ConvertTo-Json -Compress
