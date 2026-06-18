[CmdletBinding()]
param(
  [string]$TagName = "v2.6.0-cloud-auto-deploy-rc",
  [string]$Repo,
  [string]$Commit,
  [switch]$SkipVerify,
  [switch]$Json,
  [string]$FixtureDockerRunsFile,
  [string]$FixtureDeployRunsFile,
  [string]$FixtureDeployReportFile,
  [string]$FixtureVersionFile,
  [switch]$FixtureParityOk,
  [switch]$FixtureCleanWorkingTree,
  [switch]$FixtureTagAbsent,
  [switch]$WhatIfTag
)

$ErrorActionPreference = "Stop"

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

function Assert-CleanWorkingTree {
  if ($FixtureCleanWorkingTree) { return }
  $status = Invoke-GitText @("status", "--porcelain")
  if (-not [string]::IsNullOrWhiteSpace($status)) { throw "Working tree must be clean before creating an RC tag." }
}

function Test-LocalTagExists {
  param([string]$Name)
  if ($FixtureTagAbsent) { return $false }
  & git rev-parse -q --verify "refs/tags/$Name" *> $null
  return ($LASTEXITCODE -eq 0)
}

function Test-RemoteTagExists {
  param([string]$Name)
  if ($FixtureTagAbsent) { return $false }
  $raw = & git ls-remote --tags origin "refs/tags/$Name" 2>$null
  if ($LASTEXITCODE -ne 0) { throw "git ls-remote failed." }
  return -not [string]::IsNullOrWhiteSpace((($raw | Out-String).Trim()))
}

if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = Get-RepoFromRemote }
if ([string]::IsNullOrWhiteSpace($Commit)) { $Commit = Invoke-GitText @("rev-parse", "HEAD") }
$Commit = $Commit.Trim()
if ($Commit -notmatch "^[0-9a-f]{40}$") { throw "Commit must be a full 40-character SHA." }
if ($TagName -notmatch "^v[0-9]+\.[0-9]+\.[0-9]+[-A-Za-z0-9.]*$") { throw "TagName must look like a version tag." }

Assert-CleanWorkingTree
if (Test-LocalTagExists -Name $TagName) { throw "Local tag already exists: $TagName" }
if (Test-RemoteTagExists -Name $TagName) { throw "Remote tag already exists: $TagName" }

$verification = $null
if (-not $SkipVerify) {
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "skybridge-verify-cloud-autodeploy.ps1"), "-Repo", $Repo, "-Commit", $Commit, "-Json")
  if ($FixtureDockerRunsFile) { $args += @("-FixtureDockerRunsFile", $FixtureDockerRunsFile) }
  if ($FixtureDeployRunsFile) { $args += @("-FixtureDeployRunsFile", $FixtureDeployRunsFile) }
  if ($FixtureDeployReportFile) { $args += @("-FixtureDeployReportFile", $FixtureDeployReportFile) }
  if ($FixtureVersionFile) { $args += @("-FixtureVersionFile", $FixtureVersionFile) }
  if ($FixtureParityOk) { $args += "-FixtureParityOk" }
  $raw = & pwsh @args
  if ($LASTEXITCODE -ne 0) { throw "Cloud auto-deploy verification failed; refusing to create tag." }
  $verification = (($raw | Out-String).Trim() | ConvertFrom-Json)
}

if (-not $WhatIfTag) {
  & git tag -a $TagName $Commit -m "SkyBridge cloud auto-deploy RC $TagName"
  if ($LASTEXITCODE -ne 0) { throw "Failed to create annotated tag $TagName." }
  & git push origin $TagName
  if ($LASTEXITCODE -ne 0) { throw "Failed to push tag $TagName." }
}

$summary = [pscustomobject]@{
  ok = $true
  schema = "skybridge.rc_tag_creation.v1"
  tag_name = $TagName
  commit_sha = $Commit
  repo = $Repo
  verification_required = -not [bool]$SkipVerify
  verification_ok = if ($SkipVerify) { $null } else { [bool]$verification.ok }
  dry_run = [bool]$WhatIfTag
  github_release_created = $false
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  if ($WhatIfTag) { Write-Host "PASS rc tag preflight" } else { Write-Host "PASS rc tag created" }
  Write-Host "repo=$Repo"
  Write-Host "tag_name=$TagName"
  Write-Host "commit_sha=$Commit"
  Write-Host "verification_required=$($summary.verification_required)"
  Write-Host "verification_ok=$($summary.verification_ok)"
  Write-Host "github_release_created=false"
  Write-Host "token_printed=false"
}
