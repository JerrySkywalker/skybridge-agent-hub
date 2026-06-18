[CmdletBinding()]
param(
  [string]$Repo,
  [string]$Commit,
  [string]$ApiBase,
  [int]$TimeoutSeconds = 1800,
  [int]$PollSeconds = 30,
  [switch]$Json,
  [string]$FixtureDockerRunsFile,
  [string]$FixtureDeployRunsFile,
  [string]$FixtureDeployReportFile,
  [string]$FixtureVersionFile,
  [switch]$FixtureParityOk
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$ExpectedOwner = "jerryskywalker"
$ExpectedImageName = "skybridge-agent-hub-server"
Import-Module (Join-Path $PSScriptRoot "lib\Skybridge.ApiBase.psm1") -Force
$script:CurrentStage = "initializing"

function Write-Stage {
  param([string]$Name)
  $script:CurrentStage = $Name
  if (-not $Json) { Write-Host $Name }
}

function Invoke-GitText {
  param([string[]]$Arguments)
  $output = & git @Arguments 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed." }
  return (($output | Out-String).Trim())
}

function Get-RepoFromRemote {
  $remote = Invoke-GitText @("remote", "get-url", "origin")
  if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)(?:\.git)?$") {
    return "$($Matches[1])/$($Matches[2])"
  }
  throw "Unable to infer GitHub repository from origin remote. Provide -Repo owner/name."
}

function Read-JsonFile {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "JSON fixture/report file not found: $Path"
  }
  return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
}

function Invoke-GhJson {
  param([string[]]$Arguments)
  $errFile = New-TemporaryFile
  try {
    $raw = & gh @Arguments 2> $errFile
    $stderr = ""
    if (Test-Path -LiteralPath $errFile) { $stderr = Get-Content -Raw -LiteralPath $errFile }
  } finally {
    if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force }
  }
  if ($LASTEXITCODE -ne 0) {
    $safe = ConvertTo-SkybridgeSafeText -Text $stderr
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "gh command failed" }
    throw "gh $($Arguments[0..1] -join ' ') failed: $safe"
  }
  $text = (($raw | Out-String).Trim())
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }
  return ($text | ConvertFrom-Json)
}

function Get-WorkflowRuns {
  param(
    [string]$Workflow,
    [string]$ExpectedCommit,
    [string]$ExpectedRepo,
    [string]$FixtureFile
  )
  if (-not [string]::IsNullOrWhiteSpace($FixtureFile)) {
    return @(Read-JsonFile -Path $FixtureFile)
  }
  $fields = "databaseId,headSha,status,conclusion,event,createdAt"
  return @(Invoke-GhJson @("run", "list", "--repo", $ExpectedRepo, "-w", $Workflow, "--json", $fields, "--limit", "50") |
    Where-Object { [string]$_.headSha -eq $ExpectedCommit })
}

function Wait-WorkflowSuccess {
  param(
    [string]$Workflow,
    [string]$ExpectedCommit,
    [string]$ExpectedRepo,
    [string]$ExpectedEvent,
    [string]$FixtureFile
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $runs = @(Get-WorkflowRuns -Workflow $Workflow -ExpectedCommit $ExpectedCommit -ExpectedRepo $ExpectedRepo -FixtureFile $FixtureFile |
      Where-Object { [string]$_.event -eq $ExpectedEvent } |
      Sort-Object { [datetime]$_.createdAt } -Descending)
    $latest = $runs | Select-Object -First 1
    if ($null -ne $latest) {
      if ([string]$latest.status -eq "completed" -and [string]$latest.conclusion -eq "success") {
        return $latest
      }
      if ([string]$latest.status -eq "completed" -and [string]$latest.conclusion -ne "success") {
        throw "$Workflow run $($latest.databaseId) concluded $($latest.conclusion)."
      }
    }
    if (-not [string]::IsNullOrWhiteSpace($FixtureFile)) { break }
    Start-Sleep -Seconds $PollSeconds
  } while ((Get-Date) -lt $deadline)
  throw "Timed out waiting for $Workflow $ExpectedEvent run for $ExpectedCommit."
}

function Find-DeployReport {
  param([string]$Directory)
  $reports = @(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter "cloud-deploy-report.json" | Sort-Object FullName)
  if ($reports.Count -ne 1) { throw "Expected exactly one cloud-deploy-report.json under $Directory; found $($reports.Count)." }
  return $reports[0].FullName
}

function Get-DeployReport {
  param(
    [Int64]$RunId,
    [string]$ExpectedRepo
  )
  if (-not [string]::IsNullOrWhiteSpace($FixtureDeployReportFile)) {
    return [pscustomobject]@{
      path = $FixtureDeployReportFile
      value = (Read-JsonFile -Path $FixtureDeployReportFile)
    }
  }
  $target = Join-Path $RepoRoot ".agent\tmp\deploy\run-$RunId"
  if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  $errFile = New-TemporaryFile
  try {
    & gh run download $RunId --repo $ExpectedRepo --name "cloud-deploy-report" --dir $target 2> $errFile
    $stderr = ""
    if (Test-Path -LiteralPath $errFile) { $stderr = Get-Content -Raw -LiteralPath $errFile }
  } finally {
    if (Test-Path -LiteralPath $errFile) { Remove-Item -LiteralPath $errFile -Force }
  }
  if ($LASTEXITCODE -ne 0) {
    $safe = ConvertTo-SkybridgeSafeText -Text $stderr
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "artifact download failed" }
    throw "Failed to download cloud-deploy-report artifact: $safe"
  }
  $reportPath = Find-DeployReport -Directory $target
  return [pscustomobject]@{
    path = $reportPath
    value = (Read-JsonFile -Path $reportPath)
  }
}

function Assert-Equal {
  param($Actual, $Expected, [string]$Name)
  if ([string]$Actual -ne [string]$Expected) {
    throw "$Name expected '$Expected' but got '$Actual'."
  }
}

function Assert-FalseValue {
  param($Actual, [string]$Name)
  if ($Actual -ne $false) { throw "$Name expected false." }
}

function Assert-TrueValue {
  param($Actual, [string]$Name)
  if ($Actual -ne $true) { throw "$Name expected true." }
}

function Assert-DeployReport {
  param($Report, [string]$ExpectedCommit, [string]$ExpectedImageRef)
  Assert-Equal $Report.status "succeeded" "deploy_report.status"
  Assert-Equal $Report.reason "deployed" "deploy_report.reason"
  Assert-Equal $Report.rollback_status "not_used" "deploy_report.rollback_status"
  Assert-FalseValue $Report.token_printed "deploy_report.token_printed"
  Assert-Equal $Report.commit_sha $ExpectedCommit "deploy_report.commit_sha"
  Assert-Equal $Report.image_ref $ExpectedImageRef "deploy_report.image_ref"
  Assert-Equal $Report.runtime_metadata.image_tag "sha-$ExpectedCommit" "deploy_report.runtime_metadata.image_tag"
  Assert-Equal $Report.runtime_metadata.image_ref $ExpectedImageRef "deploy_report.runtime_metadata.image_ref"
  Assert-TrueValue $Report.compose_source_provided "deploy_report.compose_source_provided"
  Assert-Equal $Report.compose_install_status "installed" "deploy_report.compose_install_status"
}

function Invoke-ParityCheck {
  if ($FixtureParityOk) {
    return [pscustomobject]@{ ok = $true; deployment_parity_status = "ok"; token_printed = $false }
  }
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-cloud-parity-check.ps1") -ApiBase $ApiBase -Json 2>&1
  $text = (($raw | Out-String).Trim())
  if ($LASTEXITCODE -ne 0) {
    $detail = ConvertTo-SkybridgeSafeText -Text $text
    throw "skybridge-cloud-parity-check.ps1 failed: $detail"
  }
  try {
    return ($text | ConvertFrom-Json)
  } catch {
    throw "skybridge-cloud-parity-check.ps1 returned invalid JSON: $(ConvertTo-SkybridgeSafeText -Text $text)"
  }
}

function Get-VersionMetadata {
  if (-not [string]::IsNullOrWhiteSpace($FixtureVersionFile)) {
    return (Read-JsonFile -Path $FixtureVersionFile)
  }
  return Get-SkybridgeVersionMetadata -ApiBase $ApiBase -TimeoutSeconds 20
}

function Assert-Version {
  param($Version, [string]$ExpectedCommit, [string]$ExpectedImageRef)
  Assert-SkybridgeVersionService -Version $Version
  Assert-Equal $Version.commit_sha $ExpectedCommit "version.commit_sha"
  Assert-Equal $Version.image_tag "sha-$ExpectedCommit" "version.image_tag"
  Assert-Equal $Version.image_ref $ExpectedImageRef "version.image_ref"
  Assert-FalseValue $Version.token_printed "version.token_printed"
}

try {
  Write-Stage "[1/8] resolve repo and commit"
  if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = Get-RepoFromRemote }
  if ([string]::IsNullOrWhiteSpace($Commit)) { $Commit = Invoke-GitText @("rev-parse", "HEAD") }
  $Commit = $Commit.Trim()
  if ($Commit -notmatch "^[0-9a-f]{40}$") { throw "Commit must be a full 40-character SHA." }

  Write-Stage "[2/8] resolve SkyBridge ApiBase"
  $ApiBase = Resolve-SkybridgeApiBase -ApiBase $ApiBase -ParameterWasBound $PSBoundParameters.ContainsKey("ApiBase")
  $fixtureMode = (-not [string]::IsNullOrWhiteSpace($FixtureDockerRunsFile) -or -not [string]::IsNullOrWhiteSpace($FixtureDeployRunsFile) -or -not [string]::IsNullOrWhiteSpace($FixtureDeployReportFile) -or -not [string]::IsNullOrWhiteSpace($FixtureVersionFile) -or $FixtureParityOk)
  Assert-SkybridgeApiBaseUsable -ApiBase $ApiBase -AllowPlaceholder $fixtureMode
  if (-not $fixtureMode) {
    Assert-SkybridgeApiBaseService -ApiBase $ApiBase -TimeoutSeconds 20 | Out-Null
  } elseif (-not [string]::IsNullOrWhiteSpace($FixtureVersionFile)) {
    Assert-SkybridgeVersionService -Version (Read-JsonFile -Path $FixtureVersionFile)
  }

  $expectedImageRef = "ghcr.io/$ExpectedOwner/$ExpectedImageName`:sha-$Commit"
  Write-Stage "[3/8] wait Docker Images push workflow"
  $dockerRun = Wait-WorkflowSuccess -Workflow "Docker Images" -ExpectedCommit $Commit -ExpectedRepo $Repo -ExpectedEvent "push" -FixtureFile $FixtureDockerRunsFile
  Write-Stage "[4/8] wait Deploy Cloud workflow_run"
  $deployRun = Wait-WorkflowSuccess -Workflow "Deploy Cloud" -ExpectedCommit $Commit -ExpectedRepo $Repo -ExpectedEvent "workflow_run" -FixtureFile $FixtureDeployRunsFile
  Write-Stage "[5/8] download cloud-deploy-report artifact"
  $deployReport = Get-DeployReport -RunId ([Int64]$deployRun.databaseId) -ExpectedRepo $Repo
  Write-Stage "[6/8] validate deploy report"
  Assert-DeployReport -Report $deployReport.value -ExpectedCommit $Commit -ExpectedImageRef $expectedImageRef
  Write-Stage "[7/8] run cloud route parity"
  $parity = Invoke-ParityCheck
  if ($parity.ok -ne $true -or [string]$parity.deployment_parity_status -ne "ok") { throw "Cloud parity check failed: status=$($parity.deployment_parity_status)" }
  Assert-FalseValue $parity.token_printed "parity.token_printed"
  Write-Stage "[8/8] validate /v1/version"
  $version = Get-VersionMetadata
  Assert-Version -Version $version -ExpectedCommit $Commit -ExpectedImageRef $expectedImageRef

  $summary = [pscustomobject]@{
    ok = $true
    schema = "skybridge.cloud_autodeploy_verification.v1"
    repo = $Repo
    commit_sha = $Commit
    docker_images_run_id = [Int64]$dockerRun.databaseId
    deploy_cloud_run_id = [Int64]$deployRun.databaseId
    deploy_report_path = $deployReport.path
    deploy_report_status = $deployReport.value.status
    deploy_report_reason = $deployReport.value.reason
    cloud_parity_status = $parity.deployment_parity_status
    version_commit_sha = $version.commit_sha
    version_image_tag = $version.image_tag
    version_image_ref = $version.image_ref
    deploy_scope = $deployReport.value.deploy_scope
    compose_source_provided = [bool]$deployReport.value.compose_source_provided
    compose_install_status = $deployReport.value.compose_install_status
    rollback_status = $deployReport.value.rollback_status
    stage = "PASS summary"
    token_printed = $false
    mutated_server = $false
    triggered_deploy = $false
    created_tag = $false
  }

  if ($Json) {
    $summary | ConvertTo-Json -Depth 8
  } else {
    Write-Host "PASS summary"
    Write-Host "PASS cloud auto-deploy verification"
    Write-Host "repo=$($summary.repo)"
    Write-Host "commit_sha=$($summary.commit_sha)"
    Write-Host "docker_images_run_id=$($summary.docker_images_run_id)"
    Write-Host "deploy_cloud_run_id=$($summary.deploy_cloud_run_id)"
    Write-Host "deploy_report_status=$($summary.deploy_report_status)"
    Write-Host "deploy_report_reason=$($summary.deploy_report_reason)"
    Write-Host "cloud_parity_status=$($summary.cloud_parity_status)"
    Write-Host "version_image_ref=$($summary.version_image_ref)"
    Write-Host "rollback_status=$($summary.rollback_status)"
    Write-Host "compose_source_provided=$($summary.compose_source_provided)"
    Write-Host "compose_install_status=$($summary.compose_install_status)"
    Write-Host "token_printed=false"
  }
} catch {
  $failure = [pscustomobject]@{
    ok = $false
    schema = "skybridge.cloud_autodeploy_verification.v1"
    stage = $script:CurrentStage
    error_summary = ConvertTo-SkybridgeSafeText -Text $_.Exception.Message
    token_printed = $false
    mutated_server = $false
    triggered_deploy = $false
    created_tag = $false
  }
  if ($Json) {
    $failure | ConvertTo-Json -Depth 8
  } else {
    Write-Error "$($failure.stage): $($failure.error_summary)"
  }
  exit 1
}
