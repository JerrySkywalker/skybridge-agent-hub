$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-completion-readiness -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.readiness_state -ne "boinc_v1_alpha_two_workunit_completed") { throw "alpha is not in completed state" }
if ($json.workunit_a_completed -ne $true -or $json.workunit_b_completed -ne $true -or $json.two_workunit_alpha_completed -ne $true) { throw "two-workunit alpha completion flags mismatch" }
if ($json.workunit_c_present -ne $false -or $json.general_apply_enabled -ne $false -or $json.no_next_execution_authorized -ne $true) { throw "completion safety boundary mismatch" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-two-workunit-completed-state"; token_printed = $false } | ConvertTo-Json -Compress
