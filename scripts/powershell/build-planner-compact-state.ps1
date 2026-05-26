[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId = "self-bootstrap-smoke",
  [int]$Limit = 20,
  [switch]$Fixture,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-SafeApi {
  param([string]$Path)
  try {
    return Invoke-RestMethod -Method GET -Uri "$($ApiBase.TrimEnd('/'))$Path" -TimeoutSec 5
  } catch {
    return $null
  }
}

function ConvertFrom-CheckRollup {
  param([object[]]$StatusCheckRollup)
  $checks = @($StatusCheckRollup | ForEach-Object {
    [pscustomobject]@{ name = $_.name; status = $_.status; conclusion = $_.conclusion }
  })
  if ($checks.Count -eq 0) { return "unknown" }
  if (@($checks | Where-Object { $_.status -ne "COMPLETED" }).Count -gt 0) { return "pending" }
  if (@($checks | Where-Object { $_.conclusion -ne "SUCCESS" }).Count -gt 0) { return "failed" }
  return "green"
}

function Get-DedupeKey {
  param($Item)
  if ($Item.planner_metadata -and $Item.planner_metadata.dedupe_key) { return [string]$Item.planner_metadata.dedupe_key }
  if ($Item.dedupe_key) { return [string]$Item.dedupe_key }
  if ($Item.task_id) { return [string]$Item.task_id }
  if ($Item.title) { return (([string]$Item.title).ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-") }
  return $null
}

function Get-PrFileList {
  param([int]$Number)
  $files = @(gh pr diff $Number --name-only 2>$null)
  if ($LASTEXITCODE -ne 0) { return @() }
  return @($files)
}

function Get-OpenPrState {
  $json = gh pr list --state open --limit $Limit --json number,title,url,headRefName,isDraft,statusCheckRollup 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
  return @($json | ConvertFrom-Json | ForEach-Object {
    $files = Get-PrFileList -Number ([int]$_.number)
    [pscustomobject]@{
      number = $_.number
      title = $_.title
      url = $_.url
      branch = $_.headRefName
      draft = [bool]$_.isDraft
      changed_files = @($files)
      ci_status = ConvertFrom-CheckRollup -StatusCheckRollup @($_.statusCheckRollup)
      auto_merge_status = "unknown"
      dedupe_key = ((@($files) | Sort-Object) -join "|").ToLowerInvariant()
    }
  })
}

function Get-MergedPrState {
  $json = gh pr list --state closed --search "is:merged" --limit $Limit --json number,title,url,headRefName,mergedAt 2>$null
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($json)) { return @() }
  return @($json | ConvertFrom-Json | ForEach-Object {
    [pscustomobject]@{
      number = $_.number
      title = $_.title
      url = $_.url
      branch = $_.headRefName
      merged_at = $_.mergedAt
    }
  })
}

if ($Fixture) {
  $completedTasks = @(
    [pscustomobject]@{ task_id = "fixture-docs-runbook"; title = "Clarify Hermes PlannerAdapter runbook"; status = "completed"; dedupe_key = "docs/planner-adapter"; pr_url = "https://example.invalid/pull/1"; changed_files = @("docs/planner-adapter.md") }
  )
  $openTasks = @()
  $openPrs = @(
    [pscustomobject]@{ number = 2; title = "Task fixture docs"; url = "https://example.invalid/pull/2"; branch = "ai/edge-worker/fixture"; draft = $true; changed_files = @("docs/bootstrap-pilot.md"); ci_status = "pending"; auto_merge_status = "disabled"; dedupe_key = "docs/bootstrap-pilot" }
  )
  $mergedPrs = @()
} else {
  $taskResponse = Invoke-SafeApi -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))&goal_id=$([uri]::EscapeDataString($GoalId))&limit=$Limit"
  $tasks = if ($taskResponse -and $taskResponse.tasks) { @($taskResponse.tasks) } else { @() }
  $completedTasks = @($tasks | Where-Object { $_.status -eq "completed" } | ForEach-Object {
    [pscustomobject]@{
      task_id = $_.task_id
      title = $_.title
      status = $_.status
      dedupe_key = Get-DedupeKey -Item $_
      pr_url = $_.result.pr_url
      changed_files = @($_.planner_metadata.expected_files)
    }
  })
  $openTasks = @($tasks | Where-Object { $_.status -in @("queued", "claimed", "running", "failed", "blocked") } | ForEach-Object {
    [pscustomobject]@{
      task_id = $_.task_id
      title = $_.title
      status = $_.status
      dedupe_key = Get-DedupeKey -Item $_
      assigned_worker_id = $_.assigned_worker_id
    }
  })
  $openPrs = Get-OpenPrState
  $mergedPrs = Get-MergedPrState
}

$fileLocks = @($openPrs | ForEach-Object { @($_.changed_files) } | ForEach-Object { $_ } | Where-Object { $_ } | Sort-Object -Unique)
$dedupeKeys = @(
  @($completedTasks | ForEach-Object { $_.dedupe_key })
  @($openTasks | ForEach-Object { $_.dedupe_key })
  @($openPrs | ForEach-Object { $_.dedupe_key })
) | Where-Object { $_ } | Sort-Object -Unique

$state = [pscustomobject]@{
  schema = "skybridge.planner_compact_state.v1"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  goal_id = $GoalId
  completed_tasks = @($completedTasks)
  open_tasks = @($openTasks)
  open_prs = @($openPrs)
  merged_prs = @($mergedPrs)
  duplicate_dedupe_keys = @($dedupeKeys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
  changed_files = @($fileLocks)
  ci_status = [pscustomobject]@{
    open_green = @($openPrs | Where-Object { $_.ci_status -eq "green" }).Count
    open_pending = @($openPrs | Where-Object { $_.ci_status -eq "pending" }).Count
    open_failed = @($openPrs | Where-Object { $_.ci_status -eq "failed" }).Count
  }
  auto_merge_status = [pscustomobject]@{
    child_default = "auto_pr_auto_merge_when_policy_eligible"
    parent_default = "auto_pr_manual_merge"
    high_risk_default = "human_review_required"
  }
  do_not_repeat = @($dedupeKeys)
  locked_files = @($fileLocks)
  remaining_acceptance_status = [pscustomobject]@{
    target_rounds = 3
    completed_task_count = @($completedTasks).Count
    open_task_count = @($openTasks).Count
    open_pr_count = @($openPrs).Count
  }
  raw_prompts_included = $false
  raw_logs_included = $false
  secrets_included = $false
}

if ($Json) { $state | ConvertTo-Json -Depth 30 } else { $state | Format-List }
