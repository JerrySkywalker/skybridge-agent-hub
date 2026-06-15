$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-local-auth-common.ps1"
$gate = Invoke-LocalAuthJson "auth-gate"
Assert-LocalAuthDisabled $gate
if ($gate.auth_does_not_enable_execution -ne $true) { throw "Auth gate no-execution invariant missing." }
$exec = Invoke-LocalAuthJson "validate-request" @("-Payload", "execute=true")
if ($exec.accepted -ne $false) { throw "Execution request was accepted." }
Assert-LocalAuthDisabled $exec
Write-Host "[smoke-auth-does-not-enable-execution] ok"
