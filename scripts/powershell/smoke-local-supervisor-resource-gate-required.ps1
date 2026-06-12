$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$resource = Invoke-LocalSupervisorSmokeCommand -Command "resource-status"
Assert-TrueProperty $resource "resource_gate_required"
if ($resource.status -notin @("pass", "blocked")) { throw "Unexpected resource gate status" }
[pscustomobject]@{ ok = $true; scenario = "local-supervisor-resource-gate-required"; token_printed = $false } | ConvertTo-Json -Compress
