[CmdletBinding()]
param(
  [string]$Branch,
  [string]$Repo,
  [switch]$Json,
  [string]$FixturePrListFile
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

function Read-PrList {
  if (-not [string]::IsNullOrWhiteSpace($FixturePrListFile)) {
    return @(Get-Content -Raw -LiteralPath $FixturePrListFile | ConvertFrom-Json)
  }
  $fields = "number,url,headRefName,isDraft,mergeStateStatus,statusCheckRollup"
  $raw = & gh pr list --repo $Repo --state open --head $Branch --json $fields --limit 10 2>$null
  if ($LASTEXITCODE -ne 0) { throw "gh pr list failed." }
  $text = (($raw | Out-String).Trim())
  if ([string]::IsNullOrWhiteSpace($text)) { return @() }
  return @($text | ConvertFrom-Json)
}

function ConvertFrom-CheckRollup {
  param([object[]]$StatusCheckRollup)
  return @($StatusCheckRollup | ForEach-Object {
    $name = if ($_.name) { $_.name } elseif ($_.context) { $_.context } else { $_.workflowName }
    [pscustomobject]@{
      name = $name
      status = $_.status
      conclusion = $_.conclusion
    }
  })
}

function Test-CheckGreen {
  param($Check)
  $status = [string]$Check.status
  $conclusion = [string]$Check.conclusion
  if ($status -in @("COMPLETED", "completed") -and $conclusion -in @("SUCCESS", "success", "NEUTRAL", "neutral", "SKIPPED", "skipped")) {
    return $true
  }
  return $false
}

if ([string]::IsNullOrWhiteSpace($Repo)) { $Repo = Get-RepoFromRemote }
if ([string]::IsNullOrWhiteSpace($Branch)) { $Branch = Invoke-GitText @("branch", "--show-current") }
if ([string]::IsNullOrWhiteSpace($Branch)) { throw "Unable to infer current branch." }

$prs = @(Read-PrList)
if ($prs.Count -ne 1) { throw "Expected exactly one open PR for branch '$Branch'; found $($prs.Count)." }
$pr = $prs[0]
$checks = @(ConvertFrom-CheckRollup -StatusCheckRollup @($pr.statusCheckRollup))
$notGreen = @($checks | Where-Object { -not (Test-CheckGreen $_) })
$allGreen = ($checks.Count -gt 0 -and $notGreen.Count -eq 0)

$summary = [pscustomobject]@{
  ok = $allGreen
  schema = "skybridge.current_pr_status.v1"
  repo = $Repo
  branch = $Branch
  pr_number = [int]$pr.number
  url = $pr.url
  draft = [bool]$pr.isDraft
  merge_state = $pr.mergeStateStatus
  check_state = if ($checks.Count -eq 0) { "missing" } elseif ($allGreen) { "green" } else { "not_green" }
  checks = @($checks)
  not_green_checks = @($notGreen)
  auto_merge_attempted = $false
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 12
} else {
  Write-Host "PR #$($summary.pr_number)"
  Write-Host "branch=$($summary.branch)"
  Write-Host "draft=$($summary.draft)"
  Write-Host "merge_state=$($summary.merge_state)"
  Write-Host "check_state=$($summary.check_state)"
  foreach ($check in $checks) {
    Write-Host "check=$($check.name) status=$($check.status) conclusion=$($check.conclusion)"
  }
  Write-Host "auto_merge_attempted=false"
  Write-Host "token_printed=false"
}

if (-not $allGreen) { exit 1 }
