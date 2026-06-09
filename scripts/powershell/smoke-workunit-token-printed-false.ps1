[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
foreach ($command in @("schema", "preview", "readiness", "safe-summary", "fixture-plan")) {
  $result = Invoke-WorkunitQueue -Command $command
  Assert-TokenPrintedFalse $result
}
[pscustomobject]@{ ok = $true; scenario = "workunit-token-printed-false"; token_printed = $false } | ConvertTo-Json -Compress
