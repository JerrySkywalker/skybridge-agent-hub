$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-apply-gate -AuthorizeGoal215 -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.can_apply_workunit_a -ne $true) { throw "Workunit A should be allowed under explicit fixture authorization" }
if ($json.can_apply_workunit_b -ne $false -or @($json.allowed_workunit_ids) -contains "boinc-v1-alpha-215-workunit-b") { throw "Workunit B allowed unexpectedly" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-apply-gate-workunit-a-only"; token_printed = $false } | ConvertTo-Json -Compress
