$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-local-auth-common.ps1"
$allowed = Invoke-LocalAuthJson "origin-check" @("-Origin", "http://127.0.0.1:5173")
if ($allowed.origin -ne "allowed_loopback") { throw "Loopback origin was not allowed." }
$remote = Invoke-LocalAuthJson "origin-check" @("-Origin", "https://example.invalid")
if ($remote.origin -ne "rejected_remote") { throw "Remote origin was not rejected." }
$policy = Invoke-LocalAuthJson "loopback-check"
Assert-False $policy.remote_origins_allowed "remote_origins_allowed"
Write-Host "[smoke-auth-origin-policy] ok"
