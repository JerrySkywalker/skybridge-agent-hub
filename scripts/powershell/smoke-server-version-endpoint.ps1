[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$server = Get-Content -Raw (Join-Path $PSScriptRoot "..\..\apps\server\src\index.ts")
foreach ($needle in @("/v1/version", "skybridge.server_version.v1", "SKYBRIDGE_COMMIT_SHA", "SKYBRIDGE_IMAGE_TAG", "SKYBRIDGE_IMAGE_REF", "SKYBRIDGE_BUILD_TIME", "SKYBRIDGE_SERVER_VERSION", "token_printed: false")) {
  if ($server -notmatch [regex]::Escape($needle)) { throw "Server version endpoint contract missing: $needle" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "server-version-endpoint"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
