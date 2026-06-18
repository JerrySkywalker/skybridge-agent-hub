[CmdletBinding()]
param([switch]$Json)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmp = Join-Path $RepoRoot ".agent\tmp\goal-305-smoke"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$commit = "6df9dd689cacbe7ceae00087e30feea3c86b53ef"
$imageRef = "ghcr.io/jerryskywalker/skybridge-agent-hub-server:sha-$commit"
$dockerRunId = [Int64]27737428712
$deployRunId = [Int64]27737428713

$dockerRuns = @([pscustomobject]@{
  databaseId = $dockerRunId
  headSha = $commit
  status = "completed"
  conclusion = "success"
  event = "push"
  createdAt = "2026-06-18T01:00:00Z"
})
$deployRuns = @([pscustomobject]@{
  databaseId = $deployRunId
  headSha = $commit
  status = "completed"
  conclusion = "success"
  event = "workflow_run"
  createdAt = "2026-06-18T01:10:00Z"
})
$deployReport = [pscustomobject]@{
  schema = "skybridge.cloud_deploy_report.v1"
  status = "succeeded"
  reason = "deployed"
  deploy_scope = "skybridge-server-only"
  compose_source_provided = $true
  compose_install_status = "installed"
  rollback_status = "not_used"
  token_printed = $false
  commit_sha = $commit
  image_ref = $imageRef
  runtime_metadata = [pscustomobject]@{
    image_tag = "sha-$commit"
    image_ref = $imageRef
  }
}
$version = [pscustomobject]@{
  schema = "skybridge.server_version.v1"
  commit_sha = $commit
  image_tag = "sha-$commit"
  image_ref = $imageRef
  token_printed = $false
}

$dockerPath = Join-Path $tmp "docker-runs.json"
$deployPath = Join-Path $tmp "deploy-runs.json"
$reportPath = Join-Path $tmp "cloud-deploy-report.json"
$versionPath = Join-Path $tmp "version.json"
$dockerRuns | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $dockerPath -Encoding utf8
$deployRuns | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $deployPath -Encoding utf8
$deployReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8
$version | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $versionPath -Encoding utf8

$result = Invoke-JsonScript "skybridge-verify-cloud-autodeploy.ps1" @(
  "-Repo", "JerrySkywalker/skybridge-agent-hub",
  "-Commit", $commit,
  "-FixtureDockerRunsFile", $dockerPath,
  "-FixtureDeployRunsFile", $deployPath,
  "-FixtureDeployReportFile", $reportPath,
  "-FixtureVersionFile", $versionPath,
  "-FixtureParityOk"
)
Assert-True $result.ok "verification ok"
Assert-False $result.token_printed "token_printed"
Assert-False $result.triggered_deploy "triggered_deploy"
Assert-False $result.mutated_server "mutated_server"
if ($result.version_image_ref -ne $imageRef) { throw "version image ref mismatch." }
if ([Int64]$result.docker_images_run_id -ne $dockerRunId) { throw "docker run id mismatch." }
if ([Int64]$result.deploy_cloud_run_id -ne $deployRunId) { throw "deploy run id mismatch." }

if ($Json) { $result | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "cloud-autodeploy-verify" }
