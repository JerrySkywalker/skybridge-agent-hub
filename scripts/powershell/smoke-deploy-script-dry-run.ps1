[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
if (-not (Get-Command bash -ErrorAction SilentlyContinue)) { throw "bash is required for deploy script dry-run smoke." }
$env:SKYBRIDGE_DEPLOY_SERVICE = "skybridge-server"
$repoRootText = $repoRoot.Path
if ($repoRootText -match "^([A-Za-z]):\\(.*)$") {
  $drive = $Matches[1].ToLowerInvariant()
  $rest = $Matches[2] -replace "\\", "/"
  $bashRepoRoot = "/mnt/$drive/$rest"
} else {
  $bashRepoRoot = $repoRootText -replace "\\", "/"
}
& bash -lc "cd '$bashRepoRoot' && SKYBRIDGE_DEPLOY_REPORT_DIR='.agent/tmp/deploy' ./scripts/deploy/deploy-skybridge-server.sh --dry-run --image-ref 'ghcr.io/jerry1999-main/skybridge-agent-hub-server:sha-abc123' --commit-sha 'abc123' --expected-tag 'sha-abc123'" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Deploy dry-run failed." }
$reportPath = Join-Path $repoRoot ".agent\tmp\deploy\cloud-deploy-report.json"
$report = Get-Content -Raw $reportPath | ConvertFrom-Json
if ($report.status -ne "skipped" -or $report.reason -ne "dry_run" -or $report.token_printed -ne $false) { throw "Unexpected deploy dry-run report." }
if ($report.runtime_metadata.commit_sha -ne "abc123" -or $report.runtime_metadata.image_tag -ne "sha-abc123" -or $report.runtime_metadata.image_ref -ne "ghcr.io/jerry1999-main/skybridge-agent-hub-server:sha-abc123") {
  throw "Deploy dry-run report missing immutable runtime metadata."
}
if ($Json) { $report | ConvertTo-Json -Depth 8 -Compress } else { $report | Format-List }
