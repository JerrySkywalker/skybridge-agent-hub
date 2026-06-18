[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { throw "bash is required for compose target bounds smoke." }

$repoRootText = $repoRoot.Path
if ($repoRootText -match "^([A-Za-z]):\\(.*)$") {
  $drive = $Matches[1].ToLowerInvariant()
  $rest = $Matches[2] -replace "\\", "/"
  $bashRepoRoot = "/mnt/$drive/$rest"
} else {
  $bashRepoRoot = $repoRootText -replace "\\", "/"
}

$output = & bash -lc "cd '$bashRepoRoot' && SKYBRIDGE_DEPLOY_PATH='/tmp/skybridge-bounds-root' SKYBRIDGE_DEPLOY_COMPOSE_FILE='../escape.yml' SKYBRIDGE_DEPLOY_REPORT_DIR='.agent/tmp/deploy-bounds' ./scripts/deploy/deploy-skybridge-server.sh --dry-run --compose-source './deploy/docker-compose.skybridge.yml' --image-ref 'ghcr.io/jerry1999-main/skybridge-agent-hub-server:sha-abc123' --commit-sha 'abc123' --expected-tag 'sha-abc123'" 2>&1
if ($LASTEXITCODE -eq 0) { throw "Expected deploy script to reject compose target outside deploy path." }
if (($output -join "`n") -notmatch "compose_target_outside_deploy_path") { throw "Expected compose_target_outside_deploy_path failure." }

$summary = [pscustomobject]@{
  ok = $true
  scenario = "deploy-compose-target-bounds"
  rejected_outside_target = $true
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Compress } else { $summary | Format-List }
