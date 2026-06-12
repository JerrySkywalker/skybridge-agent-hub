$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command workunit-b-apply-gate -AuthorizeGoal216 -Json | Out-String).Trim() | ConvertFrom-Json
if (($json.can_apply_workunit_b -eq $true) -and ($json.blockers -contains "workunit_a_finalizer_required")) { throw "inconsistent Workunit B gate" }
if (($json.can_apply_workunit_b -ne $true) -and -not (@($json.blockers) -contains "workunit_a_finalizer_required")) { throw "Workunit B gate must require A finalizer when absent" }
if ($json.token_printed -ne $false) { throw "token_printed=true" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-gate-requires-a-finalized"; token_printed = $false } | ConvertTo-Json -Compress
