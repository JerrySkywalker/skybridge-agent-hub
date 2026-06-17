[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$script = Get-Content -Raw (Join-Path $PSScriptRoot "..\deploy\deploy-skybridge-server.sh")
foreach ($needle in @('SERVICE="${SKYBRIDGE_DEPLOY_SERVICE:-skybridge-server}"', 'if [[ "$SERVICE" != "skybridge-server" ]]', 'compose_cmd up -d "$SERVICE"', '"deploy_scope": "skybridge-server-only"')) {
  if ($script -notmatch [regex]::Escape($needle)) { throw "Deploy scope guard missing: $needle" }
}
foreach ($forbidden in @("docker system prune", "apt install", "apt-get install", "yum install")) {
  if ($script -match [regex]::Escape($forbidden)) { throw "Forbidden deploy script text present: $forbidden" }
}
$summary = [pscustomobject]@{ ok = $true; scenario = "deploy-scope-skybridge-server-only"; token_printed = $false }
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
