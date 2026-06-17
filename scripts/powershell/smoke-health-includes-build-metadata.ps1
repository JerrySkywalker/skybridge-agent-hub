[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$server = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\apps\server\src\index.ts")
foreach ($needle in @("commit_sha", "image_tag", "build_time", "server_version", "route_set_version", "...serverVersionMetadata()")) {
  if ($server -notmatch [regex]::Escape($needle)) { throw "Health metadata contract missing: $needle" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "health-includes-build-metadata"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
