$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.ResourceGate.psm1") -Force
$pass = Invoke-SkybridgeResourceGate -Fixture "ac-ok"
$block = Invoke-SkybridgeResourceGate -Fixture "battery-blocked"
if ($pass.can_run_one_at_a_time -ne $true) { throw "expected fixture pass" }
if ($block.can_run_one_at_a_time -ne $false) { throw "expected fixture block" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-resource-gate-fixtures"; token_printed = $false } | ConvertTo-Json -Compress
