[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$greenChecks = @(
  @{ name = "AI branch validation"; status = "COMPLETED"; conclusion = "SUCCESS" },
  @{ name = "Project check"; status = "COMPLETED"; conclusion = "SUCCESS" },
  @{ name = "Docker build (server)"; status = "COMPLETED"; conclusion = "SUCCESS" },
  @{ name = "Docker build (web)"; status = "COMPLETED"; conclusion = "SUCCESS" }
)

$fixturePrs = @(
  @{
    number = 101
    title = "Task hermes-low-risk-docs: update docs"
    body = "dedupe_key: docs/low-risk"
    url = "https://example.invalid/pull/101"
    headRefName = "ai/edge-worker/hermes-low-risk-docs"
    isDraft = $true
    mergeStateStatus = "CLEAN"
    files = @("docs/automation/low-risk.md")
    statusCheckRollup = $greenChecks
  },
  @{
    number = 102
    title = "Task hermes-duplicate-docs: update docs"
    body = "dedupe_key: docs/duplicate"
    url = "https://example.invalid/pull/102"
    headRefName = "ai/edge-worker/hermes-duplicate-a"
    isDraft = $false
    mergeStateStatus = "CLEAN"
    files = @("docs/automation/duplicate.md")
    statusCheckRollup = $greenChecks
  },
  @{
    number = 103
    title = "Task hermes-duplicate-docs: update docs again"
    body = "dedupe_key: docs/duplicate"
    url = "https://example.invalid/pull/103"
    headRefName = "ai/edge-worker/hermes-duplicate-b"
    isDraft = $false
    mergeStateStatus = "CLEAN"
    files = @("docs/automation/duplicate.md")
    statusCheckRollup = $greenChecks
  },
  @{
    number = 104
    title = "Task hermes-stale-docs: update docs"
    body = "dedupe_key: docs/stale"
    url = "https://example.invalid/pull/104"
    headRefName = "ai/edge-worker/hermes-stale"
    isDraft = $false
    mergeStateStatus = "BEHIND"
    files = @("docs/automation/stale.md")
    statusCheckRollup = $greenChecks
  },
  @{
    number = 105
    title = "Task hermes-workflow-risk: update workflow"
    body = "dedupe_key: workflow/risk"
    url = "https://example.invalid/pull/105"
    headRefName = "ai/edge-worker/hermes-workflow-risk"
    isDraft = $false
    mergeStateStatus = "CLEAN"
    files = @(".github/workflows/pr.yml")
    statusCheckRollup = $greenChecks
  },
  @{
    number = 106
    title = "Super 161 parent PR"
    body = "Parent coordination PR"
    url = "https://example.invalid/pull/106"
    headRefName = "ai/super-161-pr-lifecycle"
    isDraft = $false
    mergeStateStatus = "CLEAN"
    files = @("docs/dev/PROGRESS.md")
    statusCheckRollup = $greenChecks
  }
)

$fixtureJson = $fixturePrs | ConvertTo-Json -Depth 12 -Compress
$result = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\scripts\powershell\skybridge-merge-coordinator.ps1" -FixturePrsJson $fixtureJson -Json
if ($LASTEXITCODE -ne 0) { throw "merge coordinator fixture smoke failed" }
$parsed = $result | ConvertFrom-Json

function Assert-PrAction {
  param([int]$Number, [string]$Action, [string]$State = $null)
  $item = @($parsed.results | Where-Object { $_.pr_number -eq $Number })[0]
  if (-not $item) { throw "Missing PR #$Number in coordinator output." }
  if ($item.recommended_action -ne $Action) { throw "PR #$Number expected action $Action but got $($item.recommended_action)." }
  if ($State -and $item.lifecycle_state -ne $State) { throw "PR #$Number expected state $State but got $($item.lifecycle_state)." }
}

Assert-PrAction -Number 101 -Action "mark_ready_then_recheck" -State "draft"
Assert-PrAction -Number 102 -Action "block_duplicate" -State "duplicate"
Assert-PrAction -Number 103 -Action "block_duplicate" -State "duplicate"
Assert-PrAction -Number 104 -Action "update_branch_then_recheck" -State "stale"
Assert-PrAction -Number 105 -Action "human_review_required" -State "high_risk"
Assert-PrAction -Number 106 -Action "human_review_required"

Write-Host "[pr-lifecycle-smoke] ok duplicates=$($parsed.duplicate_count) highRisk=$($parsed.high_risk_count) stale=$($parsed.stale_count)"
