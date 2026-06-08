$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-worker-routing.ps1" -Command worker-routing-policy -Json | ConvertFrom-Json
if ($result.policy.max_parallel_per_repo -ne 1) { throw "Expected max_parallel_per_repo=1." }
if ($result.policy.can_claim_tasks -ne $false -or $result.policy.can_execute_tasks -ne $false) { throw "Policy must not enable claims or execution." }
[pscustomobject]@{ ok = $true; scenario = "worker-routing-policy"; token_printed = $false } | ConvertTo-Json -Compress
