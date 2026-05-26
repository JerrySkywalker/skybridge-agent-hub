[CmdletBinding()]
param(
  [int]$PrNumber = 0,
  [string]$PolicyFile = ".\config\merge-coordinator-policy.example.json",
  [string]$FixturePrJson,
  [string]$ComparePrsJson,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "auto-merge-policy.ps1")

function Read-MergeCoordinatorPolicy {
  param([string]$Path)
  $fallback = [pscustomobject]@{
    enabled = $true
    default_child_pr_mode = "auto_pr_auto_merge"
    default_parent_pr_mode = "auto_pr_manual_merge"
    per_project_serial_merge = $true
    allowed_auto_merge_paths = @("docs/**", "goals/**", "README.md", "CHANGELOG.md", "ROADMAP.md", "CONTRIBUTING.md")
    blocked_auto_merge_paths = @(".env", ".env.*", "**/*secret*", "**/*credential*", "**/*token*", ".github/workflows/**", "deploy/**", "production/**")
    required_checks = @("AI branch validation", "Project check", "Docker build (server)", "Docker build (web)")
    duplicate_detection = [pscustomobject]@{ enabled = $true; file_overlap_threshold = 1 }
    stale_pr_policy = [pscustomobject]@{ behind_base_is_stale = $true; pending_checks_minutes = 60; unchanged_days = 7; safe_update_branch = $true }
    conflict_policy = [pscustomobject]@{ block_conflicting_prs = $true; close_duplicates = $false; comment_before_close = $true }
    max_open_child_prs_per_project = 1
    notification_policy = [pscustomobject]@{}
  }
  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $fallback }
  $loaded = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
  foreach ($property in $fallback.PSObject.Properties) {
    if ($null -eq $loaded.PSObject.Properties[$property.Name]) {
      $loaded | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
    }
  }
  return $loaded
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

function Get-PrFromGitHub {
  param([int]$Number)
  if ($Number -le 0) { throw "PR number is required unless FixturePrJson is provided." }
  $viewJson = gh pr view $Number --json number,title,body,url,headRefName,baseRefName,isDraft,mergeStateStatus,labels,createdAt,updatedAt,statusCheckRollup 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($viewJson)) { throw "failed to read PR #$Number" }
  $view = $viewJson | ConvertFrom-Json
  $files = @(gh pr diff $Number --name-only 2>$null)
  if ($LASTEXITCODE -ne 0) { $files = @() }
  $view | Add-Member -NotePropertyName files -NotePropertyValue $files -Force
  return $view
}

function Get-TaskIdFromPr {
  param($Pr)
  $text = @($Pr.headRefName, $Pr.title, $Pr.body) -join "`n"
  if ($text -match "(?i)(hermes-[a-z0-9_.-]+-\d{14}|super-\d+[a-z]?|task[_ -]?id[:= ]+([A-Za-z0-9_.-]+))") {
    if ($Matches[2]) { return $Matches[2] }
    return $Matches[1]
  }
  return $null
}

function Get-DedupeKeyFromPr {
  param($Pr, [string[]]$Files)
  $text = @($Pr.body, $Pr.title, $Pr.headRefName) -join "`n"
  if ($text -match "(?im)dedupe_key\s*[:=]\s*([A-Za-z0-9_.:/-]+)") { return $Matches[1] }
  $taskId = Get-TaskIdFromPr -Pr $Pr
  if ($taskId) { return $taskId }
  if (@($Files).Count -gt 0) { return ((@($Files) | Sort-Object) -join "|").ToLowerInvariant() }
  return ([string]$Pr.headRefName).ToLowerInvariant()
}

function Get-PrType {
  param($Pr)
  $branch = [string]$Pr.headRefName
  $title = [string]$Pr.title
  if ($branch -like "ai/edge-worker/*" -or $title -match "(?i)^Task\s+") { return "child_task" }
  if ($branch -match "^ai/super-\d+" -or $title -match "(?i)super\s+\d+") { return "parent_super_goal" }
  if ($title -match "(?i)progress|tracking|status") { return "tracking_progress" }
  return "unknown"
}

function Get-CheckState {
  param([object[]]$Checks, [string[]]$RequiredChecks)
  $required = Test-SkyBridgeRequiredChecks -Checks $Checks -RequiredChecks $RequiredChecks
  if ($required.missing_checks.Count -gt 0) { return "missing" }
  if ($required.pending_checks.Count -gt 0) { return "pending" }
  if ($required.not_green_checks.Count -gt 0) { return "failed" }
  return "green"
}

function Find-Duplicates {
  param($Pr, [string[]]$Files, [string]$DedupeKey, [object[]]$ComparePrs, [object]$Policy)
  $matches = @()
  foreach ($other in @($ComparePrs)) {
    if ([int]$other.number -eq [int]$Pr.number) { continue }
    $otherFiles = @($other.files)
    $otherKey = if ($other.dedupe_key) { [string]$other.dedupe_key } else { Get-DedupeKeyFromPr -Pr $other -Files $otherFiles }
    $overlap = @($Files | Where-Object { $otherFiles -contains $_ })
    if ($otherKey -eq $DedupeKey -or $overlap.Count -ge [int]$Policy.duplicate_detection.file_overlap_threshold) {
      $matches += [pscustomobject]@{
        pr_number = $other.number
        url = $other.url
        state = $other.state
        dedupe_key = $otherKey
        overlapping_files = @($overlap)
      }
    }
  }
  return @($matches)
}

$policy = Read-MergeCoordinatorPolicy -Path $PolicyFile
$prInfo = if ($FixturePrJson) { $FixturePrJson | ConvertFrom-Json } else { Get-PrFromGitHub -Number $PrNumber }
$files = @($prInfo.files | ForEach-Object { ConvertTo-SkyBridgePolicyPath -Path ([string]$_) })
$checks = ConvertFrom-CheckRollup -StatusCheckRollup @($prInfo.statusCheckRollup)
$comparePrs = if ($ComparePrsJson) { @($ComparePrsJson | ConvertFrom-Json) } else { @() }

$prType = Get-PrType -Pr $prInfo
$taskId = Get-TaskIdFromPr -Pr $prInfo
$dedupeKey = Get-DedupeKeyFromPr -Pr $prInfo -Files $files
$pathPolicy = [pscustomobject]@{
  allowed_paths = @($policy.allowed_auto_merge_paths)
  blocked_paths = @($policy.blocked_auto_merge_paths)
}
$fileRisk = Test-SkyBridgeChangedFileRisk -ChangedFiles $files -Policy $pathPolicy
$checkState = Get-CheckState -Checks $checks -RequiredChecks @($policy.required_checks)
$duplicates = Find-Duplicates -Pr $prInfo -Files $files -DedupeKey $dedupeKey -ComparePrs $comparePrs -Policy $policy

$reasons = New-Object System.Collections.Generic.List[string]
foreach ($reason in @($fileRisk.reasons)) { $reasons.Add($reason) | Out-Null }
if ([bool]$prInfo.isDraft) { $reasons.Add("draft_pr") | Out-Null }
if ($checkState -eq "missing") { $reasons.Add("required_checks_missing") | Out-Null }
if ($checkState -eq "pending") { $reasons.Add("required_checks_pending") | Out-Null }
if ($checkState -eq "failed") { $reasons.Add("required_checks_failed") | Out-Null }
if ([string]$prInfo.mergeStateStatus -in @("DIRTY", "CONFLICTING")) { $reasons.Add("conflicting_pr") | Out-Null }
if ([string]$prInfo.mergeStateStatus -in @("BEHIND", "UNKNOWN")) { $reasons.Add("stale_or_unknown_base") | Out-Null }
if ($duplicates.Count -gt 0) { $reasons.Add("duplicate_pr") | Out-Null }
if ($prType -eq "parent_super_goal") { $reasons.Add("parent_manual_merge_default") | Out-Null }
if ($prType -eq "unknown") { $reasons.Add("unknown_pr_type") | Out-Null }

$risk = if ($fileRisk.risk -eq "blocked") { "high" } elseif ($fileRisk.risk -eq "needs_review" -or $prType -in @("parent_super_goal", "unknown")) { "needs_review" } else { "low" }
$lifecycleState = if ($reasons -contains "duplicate_pr") {
  "duplicate"
} elseif ($reasons -contains "conflicting_pr") {
  "conflicting"
} elseif ($reasons -contains "stale_or_unknown_base") {
  "stale"
} elseif ($risk -eq "high") {
  "high_risk"
} elseif ($checkState -eq "green" -and -not [bool]$prInfo.isDraft) {
  "ready"
} elseif ([bool]$prInfo.isDraft) {
  "draft"
} else {
  "waiting"
}

$autoMergeEligible = (
  $prType -eq "child_task" -and
  $risk -eq "low" -and
  $checkState -eq "green" -and
  -not [bool]$prInfo.isDraft -and
  $duplicates.Count -eq 0 -and
  ($reasons -notcontains "conflicting_pr") -and
  ($reasons -notcontains "stale_or_unknown_base")
)

$draftReadyCandidate = (
  $prType -eq "child_task" -and
  $risk -eq "low" -and
  $checkState -eq "green" -and
  [bool]$prInfo.isDraft -and
  $duplicates.Count -eq 0 -and
  ($reasons -notcontains "conflicting_pr") -and
  ($reasons -notcontains "stale_or_unknown_base")
)

$recommendedAction = if ($autoMergeEligible) {
  "enable_auto_merge"
} elseif ($draftReadyCandidate) {
  "mark_ready_then_recheck"
} elseif ($lifecycleState -eq "duplicate") {
  if ([bool]$policy.conflict_policy.close_duplicates) { "close_duplicate_with_comment" } else { "block_duplicate" }
} elseif ($lifecycleState -eq "conflicting") {
  "block_conflicting"
} elseif ($lifecycleState -eq "stale") {
  if ([bool]$policy.stale_pr_policy.safe_update_branch) { "update_branch_then_recheck" } else { "wait_for_manual_update" }
} elseif ($risk -eq "high") {
  "human_review_required"
} elseif ($prType -eq "parent_super_goal") {
  "human_review_required"
} else {
  "wait"
}

$result = [pscustomobject]@{
  ok = $true
  pr_number = $prInfo.number
  url = $prInfo.url
  branch = $prInfo.headRefName
  pr_type = $prType
  task_id = $taskId
  dedupe_key = $dedupeKey
  risk = $risk
  lifecycle_state = $lifecycleState
  auto_merge_eligible = [bool]$autoMergeEligible
  reasons = @($reasons | Select-Object -Unique)
  recommended_action = $recommendedAction
  changed_files = @($files)
  check_state = $checkState
  merge_state = $prInfo.mergeStateStatus
  draft = [bool]$prInfo.isDraft
  duplicates = @($duplicates)
}

if ($Json) { $result | ConvertTo-Json -Depth 20 } else { $result | Format-List }
