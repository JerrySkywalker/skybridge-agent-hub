$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$gate = Invoke-LocalSupervisorSmokeCommand -Command "no-execution-gate"
Assert-FalseProperty $gate "task_claim_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-no-task-claim"; token_printed = $false } | ConvertTo-Json -Compress
