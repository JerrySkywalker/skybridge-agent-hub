[CmdletBinding()]
param(
  [string]$PolicyFile = ".\config\merge-coordinator-policy.example.json",
  [switch]$Apply,
  [string]$FixturePrsJson,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Read-MergeCoordinatorPolicy {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "merge coordinator policy not found: $Path" }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function ConvertFrom-CheckRollup {
  param([object[]]$StatusCheckRollup)
  return @($StatusCheckRollup | ForEach-Object {
    [pscustomobject]@{ name = $_.name; status = $_.status; conclusion = $_.conclusion }
  })
}

function Get-OpenPrs {
  if ($FixturePrsJson) { return @($FixturePrsJson | ConvertFrom-Json) }

  $json = gh pr list --state open --limit 100 --json number,title,body,url,headRefName,baseRefName,isDraft,mergeStateStatus,labels,createdAt,updatedAt,statusCheckRollup
  if ($LASTEXITCODE -ne 0) { throw "failed to list open PRs" }
  return @($json | ConvertFrom-Json | ForEach-Object {
    $files = @(gh pr diff $_.number --name-only 2>$null)
    if ($LASTEXITCODE -ne 0) { $files = @() }
    $_ | Add-Member -NotePropertyName files -NotePropertyValue $files -Force
    $_
  })
}

function Invoke-Classifier {
  param($Pr, [object[]]$ComparePrs, [string]$PolicyFile)
  $prJson = $Pr | ConvertTo-Json -Depth 20 -Compress
  $compareJson = @($ComparePrs) | ConvertTo-Json -Depth 20 -Compress
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\classify-skybridge-pr.ps1" -PolicyFile $PolicyFile -FixturePrJson $prJson -ComparePrsJson $compareJson -Json
  if ($LASTEXITCODE -ne 0) { throw "classifier failed for PR #$($Pr.number)" }
  return ($output | ConvertFrom-Json)
}

function Invoke-CoordinatorAction {
  param($Classification, [object]$Policy)
  $action = [string]$Classification.recommended_action
  $prNumber = [int]$Classification.pr_number
  $result = [ordered]@{ action = $action; applied = $false; ok = $true; message = "dry-run" }
  if (-not $Apply) { return [pscustomobject]$result }

  switch ($action) {
    "enable_auto_merge" {
      if ([bool]$Classification.draft) {
        gh pr ready $prNumber | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "failed to mark PR #$prNumber ready" }
      }
      gh pr merge $prNumber --auto --squash | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "failed to enable auto-merge for PR #$prNumber" }
      $result.applied = $true
      $result.message = "enabled GitHub auto-merge"
    }
    "update_branch_then_recheck" {
      gh pr update-branch $prNumber | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "failed to update branch for PR #$prNumber" }
      $result.applied = $true
      $result.message = "requested branch update"
    }
    "close_duplicate_with_comment" {
      $comment = "SkyBridge merge coordinator classified this PR as duplicate and policy allows duplicate closure. Dedupe key: $($Classification.dedupe_key)."
      gh pr comment $prNumber --body $comment | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "failed to comment on duplicate PR #$prNumber" }
      gh pr close $prNumber | Out-Null
      if ($LASTEXITCODE -ne 0) { throw "failed to close duplicate PR #$prNumber" }
      $result.applied = $true
      $result.message = "closed duplicate with comment"
    }
    default {
      $result.message = "no mutation for recommended action"
    }
  }
  return [pscustomobject]$result
}

$policy = Read-MergeCoordinatorPolicy -Path $PolicyFile
$openPrs = Get-OpenPrs
$classifications = @()
foreach ($pr in $openPrs) {
  $classifications += Invoke-Classifier -Pr $pr -ComparePrs $openPrs -PolicyFile $PolicyFile
}

$eligible = @($classifications | Where-Object { $_.auto_merge_eligible })
$selectedEligibleNumbers = @()
if ([bool]$policy.per_project_serial_merge -and $eligible.Count -gt 0) {
  $selectedEligibleNumbers = @([int]$eligible[0].pr_number)
} else {
  $selectedEligibleNumbers = @($eligible | ForEach-Object { [int]$_.pr_number })
}

$results = @()
foreach ($classification in $classifications) {
  $effective = $classification
  if ($classification.auto_merge_eligible -and $selectedEligibleNumbers -notcontains [int]$classification.pr_number) {
    $effective = $classification.PSObject.Copy()
    $effective.auto_merge_eligible = $false
    $effective.recommended_action = "wait_serial_merge"
    $effective.reasons = @(@($effective.reasons) + "serial_merge_wait")
  }
  $actionResult = Invoke-CoordinatorAction -Classification $effective -Policy $policy
  $results += [pscustomobject]@{
    pr_number = $effective.pr_number
    url = $effective.url
    branch = $effective.branch
    pr_type = $effective.pr_type
    risk = $effective.risk
    lifecycle_state = $effective.lifecycle_state
    auto_merge_eligible = [bool]$effective.auto_merge_eligible
    reasons = @($effective.reasons)
    recommended_action = $effective.recommended_action
    action_result = $actionResult
    changed_files = @($effective.changed_files)
    duplicates = @($effective.duplicates)
  }
}

$summary = [pscustomobject]@{
  ok = $true
  dry_run = -not [bool]$Apply
  apply_requested = [bool]$Apply
  per_project_serial_merge = [bool]$policy.per_project_serial_merge
  total_open_prs = $openPrs.Count
  eligible_count = @($results | Where-Object { $_.auto_merge_eligible }).Count
  high_risk_count = @($results | Where-Object { $_.risk -eq "high" }).Count
  duplicate_count = @($results | Where-Object { $_.lifecycle_state -eq "duplicate" }).Count
  conflicting_count = @($results | Where-Object { $_.lifecycle_state -eq "conflicting" }).Count
  stale_count = @($results | Where-Object { $_.lifecycle_state -eq "stale" }).Count
  results = @($results)
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 30
} else {
  Write-Host "[merge-coordinator] dryRun=$($summary.dry_run) open=$($summary.total_open_prs) eligible=$($summary.eligible_count) duplicate=$($summary.duplicate_count) highRisk=$($summary.high_risk_count)"
  foreach ($result in $summary.results) {
    Write-Host "[merge-coordinator] PR #$($result.pr_number) type=$($result.pr_type) state=$($result.lifecycle_state) action=$($result.recommended_action) reasons=$($result.reasons -join ',')"
  }
}
