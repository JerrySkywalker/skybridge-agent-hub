$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-apply-gate -AuthorizeGoal216 -SimulateWorkunitAFinalized -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.max_apply_workunits -ne 1 -or @($json.allowed_workunit_ids).Count -gt 1) { throw "Workunit B gate must allow at most one workunit" }
if ($json.workunit_c_present -ne $false) { throw "Workunit C must be absent" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-apply-one-workunit"; token_printed = $false } | ConvertTo-Json -Compress
