$ErrorActionPreference = "Stop"
$desktop = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "..\..\apps\desktop\src\main.tsx")
foreach ($required in @("Resident Status", "Worker Supervisor", "Resource Policy", "EXECUTION DISABLED")) {
  if ($desktop -notmatch [regex]::Escape($required)) { throw "Desktop resident visual fixture missing: $required" }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-resident-visual-qa"; fixture_checked = $true; token_printed = $false } | ConvertTo-Json -Compress
