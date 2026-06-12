$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-hold-report -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.workunit_b_state -ne "blocked_by_unfinalized_workunit_a") { throw "expected Workunit B blocked hold state" }
if ($json.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-hold-report"; token_printed = $false } | ConvertTo-Json -Compress
