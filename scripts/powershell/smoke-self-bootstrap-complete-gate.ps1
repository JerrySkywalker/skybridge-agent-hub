$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command gate -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.self_bootstrap_complete_gate.v1") { throw "Unexpected gate schema." }
if ($result.gate_pass -ne $true) { throw "Bootstrap complete gate did not pass." }
if (@($result.blockers).Count -ne 0) { throw "Bootstrap complete gate has blockers." }
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-complete-gate"; token_printed = $false } | ConvertTo-Json
