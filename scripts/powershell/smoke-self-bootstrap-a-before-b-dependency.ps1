$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command gate -Json | ConvertFrom-Json
if ($result.gate_pass -ne $true) { throw "Bootstrap gate must pass before dependency smoke." }
$trial = Get-Content -LiteralPath (Join-Path (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path ".agent/tmp/server-approved-two-workunit-trial-226/two-workunit-trial-report.json") -Raw | ConvertFrom-Json
if ($trial.workunit_a_completed -ne $true -or $trial.workunit_b_completed -ne $true) { throw "A/B completion missing." }
if ($trial.final_state -ne "server_approved_two_workunit_trial_226_completed") { throw "Trial final state is not complete." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-a-before-b-dependency"; token_printed = $false } | ConvertTo-Json
