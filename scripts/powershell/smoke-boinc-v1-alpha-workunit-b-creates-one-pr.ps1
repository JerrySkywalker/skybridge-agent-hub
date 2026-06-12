$ErrorActionPreference = "Stop"
$script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "skybridge-boinc-v1-alpha.ps1")
foreach ($required in @("BOINC v1 Alpha 215 Workunit B:", "gh pr create", "ai/boinc-v1-alpha/boinc-v1-alpha-215-workunit-b")) {
  if ($script -notlike "*$required*") { throw "missing Workunit B PR packaging marker: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "boinc-v1-alpha-workunit-b-creates-one-pr"; token_printed = $false } | ConvertTo-Json -Compress
