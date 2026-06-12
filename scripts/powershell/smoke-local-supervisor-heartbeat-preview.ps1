$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$heartbeat = Invoke-LocalSupervisorSmokeCommand -Command "heartbeat-preview"
if ($heartbeat.schema -ne "skybridge.local_supervisor_heartbeat.v1") { throw "Unexpected heartbeat preview schema" }
Assert-FalseProperty $heartbeat "execution_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-heartbeat-preview"; token_printed = $false } | ConvertTo-Json -Compress
