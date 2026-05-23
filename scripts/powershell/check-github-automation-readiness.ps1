[CmdletBinding()]
param(
  [string]$ConfigFile = ".\config\iteration-controller.example.json",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Test-CommandAvailable {
  param([string]$Name)
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Add-Finding {
  param(
    [string]$Name,
    [ValidateSet("ready", "warning", "blocker", "manual_setup_required")]
    [string]$Status,
    [string]$Detail,
    [object]$Data = $null
  )

  $item = [ordered]@{
    name = $Name
    status = $Status
    detail = $Detail
  }
  if ($null -ne $Data) { $item["data"] = $Data }
  $script:findings += $item
}

function Invoke-GhJson {
  param([string[]]$Arguments)
  try {
    $output = & gh @Arguments 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output -join ""))) {
      return @{ ok = $false; value = $null; raw = $output }
    }
    return @{ ok = $true; value = (($output -join "`n") | ConvertFrom-Json); raw = $output }
  } catch {
    return @{ ok = $false; value = $null; error = $_.Exception.Message }
  }
}

function Get-Config {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$script:findings = @()
$mutatedRemoteSettings = $false
$branchProtectionMutated = $false
$config = Get-Config -Path $ConfigFile

$gitAvailable = Test-CommandAvailable "git"
$ghAvailable = Test-CommandAvailable "gh"
$codexAvailable = Test-CommandAvailable "codex"
$corepackAvailable = Test-CommandAvailable "corepack"

Add-Finding -Name "git" -Status ($(if ($gitAvailable) { "ready" } else { "blocker" })) -Detail "Git CLI availability."
Add-Finding -Name "gh" -Status ($(if ($ghAvailable) { "ready" } else { "warning" })) -Detail "GitHub CLI availability for remote readiness inspection."
Add-Finding -Name "codex" -Status ($(if ($codexAvailable) { "ready" } else { "warning" })) -Detail "Codex CLI availability for local autonomous workers."
Add-Finding -Name "corepack" -Status ($(if ($corepackAvailable) { "ready" } else { "blocker" })) -Detail "Corepack availability for project checks."
Add-Finding -Name "config" -Status ($(if ($config) { "ready" } else { "warning" })) -Detail $ConfigFile

if ($gitAvailable) {
  try {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null) -join ""
    Add-Finding -Name "git_repo" -Status ($(if ($LASTEXITCODE -eq 0 -and $repoRoot) { "ready" } else { "blocker" })) -Detail "Current directory is inside a Git repository." -Data @{ root = $repoRoot }
  } catch {
    Add-Finding -Name "git_repo" -Status "blocker" -Detail $_.Exception.Message
  }

  $remoteUrl = (& git config --get remote.origin.url 2>$null) -join ""
  Add-Finding -Name "git_remote" -Status ($(if ($remoteUrl) { "ready" } else { "blocker" })) -Detail "Origin remote configured." -Data @{ remote = if ($remoteUrl) { "configured" } else { "missing" } }
}

$workflowFiles = @(Get-ChildItem -LiteralPath ".\.github\workflows" -Filter "*.yml" -File -ErrorAction SilentlyContinue)
if ($workflowFiles.Count -gt 0) {
  Add-Finding -Name "local_workflows" -Status "ready" -Detail "Workflow files are present locally." -Data @{ workflows = @($workflowFiles.Name) }
} else {
  Add-Finding -Name "local_workflows" -Status "blocker" -Detail "No local GitHub Actions workflows were found."
}

if ($config -and $config.github -and $config.github.autoMerge -eq $true) {
  Add-Finding -Name "config_auto_merge" -Status "manual_setup_required" -Detail "Project config enables auto-merge; verify branch protection manually before use."
} else {
  Add-Finding -Name "config_auto_merge" -Status "ready" -Detail "Project config leaves auto-merge disabled by default."
}

if ($ghAvailable) {
  try {
    $auth = & gh auth status 2>&1
    Add-Finding -Name "gh_auth" -Status ($(if ($LASTEXITCODE -eq 0) { "ready" } else { "warning" })) -Detail (($auth | Select-Object -First 1) -join "")
  } catch {
    Add-Finding -Name "gh_auth" -Status "warning" -Detail $_.Exception.Message
  }

  $repoView = Invoke-GhJson -Arguments @("repo", "view", "--json", "nameWithOwner,defaultBranchRef,isPrivate,viewerPermission,autoMergeAllowed")
  if ($repoView.ok) {
    $repo = $repoView.value
    Add-Finding -Name "current_repo" -Status "ready" -Detail "GitHub repository metadata is visible." -Data @{
      nameWithOwner = $repo.nameWithOwner
      defaultBranch = $repo.defaultBranchRef.name
      isPrivate = $repo.isPrivate
      viewerPermission = $repo.viewerPermission
    }
    $autoMergeStatus = if ($repo.autoMergeAllowed -eq $true) { "ready" } else { "manual_setup_required" }
    Add-Finding -Name "github_auto_merge" -Status $autoMergeStatus -Detail "GitHub reports whether repository auto-merge is allowed." -Data @{ autoMergeAllowed = [bool]$repo.autoMergeAllowed }
  } else {
    Add-Finding -Name "current_repo" -Status "warning" -Detail "GitHub repository metadata could not be inspected with gh."
    Add-Finding -Name "github_auto_merge" -Status "manual_setup_required" -Detail "Auto-merge availability could not be verified; inspect repository settings manually."
  }

  $prs = Invoke-GhJson -Arguments @("pr", "list", "--state", "open", "--limit", "20", "--json", "number,title,isDraft,headRefName,baseRefName,mergeStateStatus,url")
  if ($prs.ok) {
    Add-Finding -Name "open_prs" -Status "ready" -Detail "Open pull requests are visible." -Data @{ count = @($prs.value).Count; prs = @($prs.value | Select-Object number,isDraft,headRefName,baseRefName,mergeStateStatus,url) }
  } else {
    Add-Finding -Name "open_prs" -Status "warning" -Detail "Open pull requests could not be inspected."
  }

  $workflowList = Invoke-GhJson -Arguments @("workflow", "list", "--json", "id,name,path,state")
  if ($workflowList.ok) {
    $workflows = @($workflowList.value)
    $activeCount = @($workflows | Where-Object { $_.state -eq "active" }).Count
    Add-Finding -Name "remote_workflows" -Status ($(if ($activeCount -gt 0) { "ready" } else { "blocker" })) -Detail "GitHub Actions workflows are visible remotely." -Data @{ active = $activeCount; workflows = @($workflows | Select-Object name,path,state) }
  } else {
    Add-Finding -Name "remote_workflows" -Status "warning" -Detail "Remote workflow list could not be inspected."
  }

  $runs = Invoke-GhJson -Arguments @("run", "list", "--limit", "10", "--json", "databaseId,displayTitle,workflowName,status,conclusion,event,headBranch,createdAt,url")
  if ($runs.ok) {
    $runItems = @($runs.value)
    $failed = @($runItems | Where-Object { $_.conclusion -in @("failure", "cancelled", "timed_out", "action_required") })
    $status = if ($runItems.Count -eq 0) { "warning" } elseif ($failed.Count -gt 0) { "warning" } else { "ready" }
    Add-Finding -Name "latest_workflow_results" -Status $status -Detail "Latest GitHub Actions workflow results inspected." -Data @{ count = $runItems.Count; failing = $failed.Count; runs = @($runItems | Select-Object workflowName,status,conclusion,event,headBranch,url) }
  } else {
    Add-Finding -Name "latest_workflow_results" -Status "warning" -Detail "Latest workflow results could not be inspected."
  }

  Add-Finding -Name "branch_protection" -Status "manual_setup_required" -Detail "This checker does not mutate or fully prove branch protection; verify required PRs, checks, force-push policy and auto-merge manually."
} else {
  Add-Finding -Name "remote_inspection" -Status "warning" -Detail "Install and authenticate GitHub CLI to inspect repository, PR and workflow state."
  Add-Finding -Name "branch_protection" -Status "manual_setup_required" -Detail "Manual GitHub branch protection review is required because gh is unavailable."
}

$statusRank = @{
  ready = 0
  warning = 1
  manual_setup_required = 2
  blocker = 3
}
$overall = "ready"
foreach ($finding in $findings) {
  if ($statusRank[$finding.status] -gt $statusRank[$overall]) { $overall = $finding.status }
}

$summary = [ordered]@{
  ok = $overall -ne "blocker"
  overall = $overall
  ready = $overall -eq "ready"
  warning_count = @($findings | Where-Object { $_.status -eq "warning" }).Count
  blocker_count = @($findings | Where-Object { $_.status -eq "blocker" }).Count
  manual_setup_required_count = @($findings | Where-Object { $_.status -eq "manual_setup_required" }).Count
  modified_remote_settings = $mutatedRemoteSettings
  branch_protection_mutated = $branchProtectionMutated
  required_local_commands = @(
    "corepack pnpm check",
    "pwsh -ExecutionPolicy Bypass -File ./scripts/powershell/validate-powershell.ps1"
  )
  manual_setup_required = @(
    "Enable GitHub branch protection for the base branch.",
    "Require pull requests before merging.",
    "Require the project check workflow before merge.",
    "Disable force pushes.",
    "Enable repository auto-merge only after required checks are proven."
  )
  findings = $findings
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 12
} else {
  foreach ($finding in $findings) {
    Write-Host "[github-readiness] $($finding.status) $($finding.name): $($finding.detail)"
  }
  Write-Host "[github-readiness] overall=$overall branch_protection_mutated=$branchProtectionMutated remote_settings_mutated=$mutatedRemoteSettings"
}

exit 0
