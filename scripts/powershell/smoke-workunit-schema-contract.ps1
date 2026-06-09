[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$schema = Invoke-WorkunitQueue -Command schema
foreach ($required in @(
  "skybridge.workunit.v1",
  "skybridge.workunit_state.v1",
  "skybridge.workunit_lease.v1",
  "skybridge.workunit_result.v1",
  "skybridge.bounded_queue_plan.v1",
  "skybridge.bounded_queue_readiness.v1",
  "skybridge.bounded_queue_policy.v1"
)) {
  if ($required -notin @($schema.schemas)) { throw "Missing schema $required." }
}
if ($schema.apply_available) { throw "apply must not be available." }
Assert-TokenPrintedFalse $schema
[pscustomobject]@{ ok = $true; scenario = "workunit-schema-contract"; token_printed = $false } | ConvertTo-Json -Compress
