$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-bootstrap-complete.ps1" -Command status -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.self_bootstrap_complete_status.v1") { throw "Unexpected status schema." }
if ($result.bootstrap_complete -ne $true) { throw "Bootstrap status is not complete." }
if ($result.remote_execution_enabled -ne $false) { throw "Remote execution must remain disabled." }
if ($result.arbitrary_command_enabled -ne $false) { throw "Arbitrary command dispatch must remain disabled." }
if ($result.execution_enabled -ne $false) { throw "Execution must remain globally disabled." }
if ($result.queue_apply_enabled -ne $false) { throw "Queue apply must remain globally disabled." }
if ($result.no_next_execution_authorized -ne $true) { throw "No next execution must be authorized." }
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "self-bootstrap-complete-status"; token_printed = $false } | ConvertTo-Json
