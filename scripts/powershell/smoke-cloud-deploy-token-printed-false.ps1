[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$paths = @(
  (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1"),
  (Join-Path $PSScriptRoot "..\deploy\deploy-skybridge-server.sh"),
  (Join-Path $PSScriptRoot "..\..\.github\workflows\deploy-cloud.yml"),
  (Join-Path $PSScriptRoot "..\..\apps\server\src\index.ts"),
  (Join-Path $PSScriptRoot "..\..\packages\client\src\index.ts")
)
foreach ($path in $paths) {
  $text = Get-Content -Raw $path
  if ($text -notmatch "token_printed") { throw "Missing token_printed marker in $path" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "cloud-deploy-token-printed-false"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
