$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$state = Invoke-LocalSupervisorSmokeCommand -Command "pause-preview"
Assert-TrueProperty $state "pause_after_current"
Assert-TrueProperty $state "pause_new_claims"
Assert-FalseProperty $state "execution_enabled"
Assert-FalseProperty $state "queue_apply_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-pause-preview-only"; token_printed = $false } | ConvertTo-Json -Compress
