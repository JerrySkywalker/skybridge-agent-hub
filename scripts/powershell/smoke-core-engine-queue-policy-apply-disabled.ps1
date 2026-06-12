$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.QueuePolicy.psm1") -Force
$policy = New-SkybridgeTwoWorkunitPreviewPolicy
if ($policy.apply_enabled -ne $false -or $policy.max_apply_workunits -ne 0 -or $policy.no_next_execution_authorized -ne $true) { throw "queue apply should be disabled" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-queue-policy-apply-disabled"; token_printed = $false } | ConvertTo-Json -Compress
