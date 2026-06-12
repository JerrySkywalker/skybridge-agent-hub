$ErrorActionPreference = "Stop"
$json = (& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1") -Command alpha-apply-gate -AuthorizeGoal215 -SimulateResourceGateFail -Json | Out-String).Trim() | ConvertFrom-Json
if ($json.resource_gate.resource_gate_required -ne $true) { throw "resource gate must be required" }
if (@($json.blockers) -notcontains "resource_gate_blocked") { throw "resource gate failure should block" }
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-resource-gate-required"; token_printed = $false } | ConvertTo-Json -Compress
