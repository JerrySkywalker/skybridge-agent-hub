[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$workflow = Get-Content -Raw (Join-Path $repoRoot ".github\workflows\deploy-cloud.yml")
$script = Get-Content -Raw (Join-Path $repoRoot "scripts\deploy\deploy-skybridge-server.sh")

foreach ($needle in @(
  "deploy/docker-compose.skybridge.yml",
  "/tmp/docker-compose.skybridge.yml",
  "--compose-source /tmp/docker-compose.skybridge.yml"
)) {
  if ($workflow -notmatch [regex]::Escape($needle)) { throw "Deploy workflow compose sync contract missing: $needle" }
}

foreach ($needle in @(
  "--compose-source",
  "resolve_path_under_deploy_path",
  "COMPOSE_TARGET",
  "COMPOSE_BACKUP_PATH",
  "compose_target_outside_deploy_path",
  "restore_compose_if_needed",
  "compose-backups"
)) {
  if ($script -notmatch [regex]::Escape($needle)) { throw "Deploy script compose sync contract missing: $needle" }
}

if ($workflow -match [regex]::Escape("rsync")) { throw "Deploy workflow must not rsync the repository." }

$summary = [pscustomobject]@{
  ok = $true
  scenario = "deploy-compose-sync-contract"
  deploy_scope = "skybridge-server-only"
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
