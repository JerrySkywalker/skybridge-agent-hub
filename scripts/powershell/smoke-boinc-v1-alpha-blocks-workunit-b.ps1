$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-workunit-b-preview -AuthorizeGoal215 -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.status -ne "blocked_by_unfinalized_workunit_a" -or $json.apply_enabled_for_this_goal -ne $false) { throw "Workunit B must be blocked" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-blocks-workunit-b"; token_printed = $false } | ConvertTo-Json -Compress
