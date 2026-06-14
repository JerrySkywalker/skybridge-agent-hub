$ErrorActionPreference = "Stop"
$result = & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-smoke-matrix.ps1" -Command list -Json | ConvertFrom-Json
if ($result.schema -ne "skybridge.smoke_matrix.v1") { throw "Unexpected smoke matrix schema." }
foreach ($group in @("fast", "release", "bootstrap-complete", "control-plane", "resident", "trusted-docs", "failure-budget", "evidence-retention", "audit-redaction", "workunit-safe", "desktop", "web")) {
  if (@($result.groups | Where-Object { $_.name -eq $group }).Count -ne 1) { throw "Missing smoke group $group." }
}
if ($result.token_printed -ne $false) { throw "Token invariant failed." }
[pscustomobject]@{ ok = $true; smoke = "smoke-matrix-list"; token_printed = $false } | ConvertTo-Json
