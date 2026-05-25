[CmdletBinding()]
param(
  [string]$PolicyFile,
  [switch]$EnableAutoMerge,
  [switch]$AllowPendingRequiredChecks,
  [switch]$NotifyBootstrap,
  [switch]$SuppressBlockedNotifications,
  [switch]$Json,
  [switch]$Fixture,
  [ValidateSet("Mixed", "NoEligible", "BlockedHighRisk")]
  [string]$FixtureScenario = "Mixed"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "auto-merge-policy.ps1")

$policy = Read-SkyBridgeAutoMergePolicy -PolicyFile $PolicyFile
$dryRun = -not [bool]$EnableAutoMerge

function Invoke-SweepBootstrapNotification {
  param([string]$Severity, [string]$Title, [string]$Message)
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\notify-bootstrap.ps1" `
    -Title $Title `
    -Message $Message `
    -Severity $Severity | Out-Host
}

function ConvertFrom-CheckRollup {
  param([object[]]$StatusCheckRollup)
  return @($StatusCheckRollup | ForEach-Object {
    [pscustomobject]@{
      name = $_.name
      status = $_.status
      conclusion = $_.conclusion
    }
  })
}

function Get-OpenPullRequests {
  if ($Fixture) {
    $checks = @($policy.required_checks | ForEach-Object {
      [pscustomobject]@{ name = $_; status = "COMPLETED"; conclusion = "SUCCESS" }
    })
    if ($FixtureScenario -eq "NoEligible") {
      return @(
        [pscustomobject]@{
          number = 201
          title = "fixture draft docs"
          url = "https://example.invalid/pull/201"
          headRefName = "ai/fixture-draft-docs"
          isDraft = $true
          files = @("docs/automation/draft.md")
          checks = $checks
        },
        [pscustomobject]@{
          number = 202
          title = "fixture human docs"
          url = "https://example.invalid/pull/202"
          headRefName = "feature/human-docs"
          isDraft = $false
          files = @("docs/automation/human.md")
          checks = $checks
        }
      )
    }
    if ($FixtureScenario -eq "BlockedHighRisk") {
      return @(
        [pscustomobject]@{
          number = 301
          title = "fixture blocked workflow"
          url = "https://example.invalid/pull/301"
          headRefName = "ai/fixture-blocked-workflow"
          isDraft = $false
          files = @(".github/workflows/pr.yml")
          checks = $checks
        }
      )
    }
    return @(
      [pscustomobject]@{
        number = 101
        title = "fixture docs"
        url = "https://example.invalid/pull/101"
        headRefName = "ai/fixture-docs"
        isDraft = $false
        files = @("docs/automation/fixture.md")
        checks = $checks
      },
      [pscustomobject]@{
        number = 102
        title = "fixture workflow"
        url = "https://example.invalid/pull/102"
        headRefName = "ai/fixture-workflow"
        isDraft = $false
        files = @(".github/workflows/pr.yml")
        checks = $checks
      },
      [pscustomobject]@{
        number = 103
        title = "fixture draft"
        url = "https://example.invalid/pull/103"
        headRefName = "ai/fixture-draft"
        isDraft = $true
        files = @("docs/automation/draft.md")
        checks = $checks
      }
    )
  }

  $json = gh pr list --state open --limit 100 --json number,title,url,headRefName,isDraft,statusCheckRollup
  if ($LASTEXITCODE -ne 0) {
    throw "failed to list open pull requests"
  }

  return @($json | ConvertFrom-Json | ForEach-Object {
    $files = @(gh pr diff $_.number --name-only 2>$null)
    if ($LASTEXITCODE -ne 0) {
      $files = @()
    }
    [pscustomobject]@{
      number = $_.number
      title = $_.title
      url = $_.url
      headRefName = $_.headRefName
      isDraft = $_.isDraft
      files = $files
      checks = ConvertFrom-CheckRollup -StatusCheckRollup $_.statusCheckRollup
    }
  })
}

$results = New-Object System.Collections.Generic.List[object]
$pullRequests = Get-OpenPullRequests

foreach ($pr in $pullRequests) {
  $eligibility = Test-SkyBridgeAutoMergeEligibility `
    -PrInfo $pr `
    -ChangedFiles @($pr.files) `
    -Checks @($pr.checks) `
    -Policy $policy `
    -AllowPendingChecks:$AllowPendingRequiredChecks

  $action = "skip"
  $message = "not eligible"
  if ($eligibility.eligible) {
    if ($EnableAutoMerge) {
      gh pr merge $pr.number --auto --squash
      if ($LASTEXITCODE -ne 0) {
        $action = "error"
        $message = "failed to enable GitHub auto-merge"
      } else {
        $action = "enabled_auto_merge"
        $message = "GitHub auto-merge enabled"
      }
    } else {
      $action = "dry_run_eligible"
      $message = "eligible; dry-run only"
    }
  }

  if ($eligibility.eligible -and $NotifyBootstrap) {
    Invoke-SweepBootstrapNotification -Severity "info" -Title "SkyBridge auto-merge sweep" -Message "PR #$($pr.number) is eligible: $message"
  }

  if (-not $eligibility.eligible -and -not $SuppressBlockedNotifications) {
    $risk = [string]$eligibility.file_risk.risk
    if ($risk -in @("blocked", "needs_review") -or $eligibility.reasons -contains "draft_pr") {
      Invoke-SweepBootstrapNotification -Severity "warning" -Title "SkyBridge auto-merge skipped" -Message "PR #$($pr.number) skipped: $($eligibility.reasons -join ', ')"
    }
  }

  $results.Add([pscustomobject]@{
    pr_number = $pr.number
    title = $pr.title
    url = $pr.url
    branch = $pr.headRefName
    draft = [bool]$pr.isDraft
    eligible = [bool]$eligibility.eligible
    action = $action
    message = $message
    reasons = @($eligibility.reasons)
    file_risk = $eligibility.file_risk.risk
    blocked_files = @($eligibility.file_risk.blocked_files)
    outside_allowed_files = @($eligibility.file_risk.outside_allowed_files)
    missing_checks = @($eligibility.checks.missing_checks)
    pending_checks = @($eligibility.checks.pending_checks)
    not_green_checks = @($eligibility.checks.not_green_checks)
  }) | Out-Null
}

$resultArray = @($results.ToArray())
$eligibleCount = 0
$skippedCount = 0
foreach ($result in $resultArray) {
  if ([bool]$result.eligible) {
    $eligibleCount += 1
  } else {
    $skippedCount += 1
  }
}

$summary = [pscustomobject]@{
  ok = $true
  dry_run = $dryRun
  auto_merge_requested = [bool]$EnableAutoMerge
  policy_enabled = [bool]$policy.enabled
  fixture = [bool]$Fixture
  fixture_scenario = if ($Fixture) { $FixtureScenario } else { $null }
  total_open_prs = $pullRequests.Count
  eligible_count = $eligibleCount
  skipped_count = $skippedCount
  policy_counts = [pscustomobject]@{
    eligible = $eligibleCount
    blocked = @($resultArray | Where-Object { $_.reasons -contains "blocked_path" }).Count
    draft = @($resultArray | Where-Object { $_.reasons -contains "draft_pr" }).Count
    non_ai_branch = @($resultArray | Where-Object { $_.reasons -contains "branch_prefix_not_allowed" }).Count
    high_risk_files = @($resultArray | Where-Object { $_.file_risk -in @("blocked", "needs_review") }).Count
    missing_checks = @($resultArray | Where-Object { @($_.missing_checks).Count -gt 0 }).Count
    pending_checks = @($resultArray | Where-Object { @($_.pending_checks).Count -gt 0 }).Count
  }
  results = $resultArray
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 12
} else {
  Write-Host "[auto-merge-sweep] dryRun=$dryRun open=$($summary.total_open_prs) eligible=$($summary.eligible_count) skipped=$($summary.skipped_count)"
  foreach ($result in $summary.results) {
    Write-Host "[auto-merge-sweep] PR #$($result.pr_number) $($result.action) branch=$($result.branch) risk=$($result.file_risk) reasons=$($result.reasons -join ',')"
  }
}
