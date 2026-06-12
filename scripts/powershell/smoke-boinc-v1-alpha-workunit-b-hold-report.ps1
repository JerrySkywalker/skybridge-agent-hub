$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-hold-report -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.no_next_execution_authorized -ne $true) { throw "Workunit B hold report must keep next execution unauthorized" }
if ($json.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-hold-report"; token_printed = $false } | ConvertTo-Json -Compress
