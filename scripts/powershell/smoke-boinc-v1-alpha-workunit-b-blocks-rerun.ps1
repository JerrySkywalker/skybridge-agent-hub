$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-finalizer-report -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.workunit_b_completed -ne $true -or $json.workunit_b_rerun_blocked -ne $true) { throw "Workunit B rerun is not blocked by finalizer report" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-blocks-rerun"; token_printed = $false } | ConvertTo-Json -Compress
