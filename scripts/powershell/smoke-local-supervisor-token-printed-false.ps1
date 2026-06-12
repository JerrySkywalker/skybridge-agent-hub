$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
foreach ($command in @("status", "heartbeat-once", "heartbeat-preview", "lock-status", "stale-lock-check", "resource-status", "resident-summary", "pause-preview", "drain-preview", "emergency-stop-preview", "control-state", "action-matrix", "evidence-summary", "no-execution-gate", "safe-report")) {
  $null = Invoke-LocalSupervisorSmokeCommand -Command $command
}
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
