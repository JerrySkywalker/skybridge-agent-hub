$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$state = Invoke-LocalSupervisorSmokeCommand -Command "emergency-stop-preview"
Assert-TrueProperty $state "emergency_stop_requested"
Assert-FalseProperty $state "execution_enabled"
Assert-FalseProperty $state "queue_apply_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-emergency-stop-preview-only"; token_printed = $false } | ConvertTo-Json -Compress
