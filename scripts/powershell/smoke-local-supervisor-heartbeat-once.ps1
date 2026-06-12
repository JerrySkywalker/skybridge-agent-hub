$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$heartbeat = Invoke-LocalSupervisorSmokeCommand -Command "heartbeat-once"
if ($heartbeat.schema -ne "skybridge.local_supervisor_heartbeat.v1") { throw "Unexpected heartbeat schema" }
if (-not (Test-Path -LiteralPath $heartbeat.heartbeat_path)) { throw "Heartbeat path missing" }
Assert-FalseProperty $heartbeat "execution_enabled"
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-heartbeat-once"; heartbeat_path = $heartbeat.heartbeat_path; token_printed = $false } | ConvertTo-Json -Compress
