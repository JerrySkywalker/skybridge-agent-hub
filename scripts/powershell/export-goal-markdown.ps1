[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$GoalId,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$OutFile,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function Convert-ArrayToBullets {
  param($Items)
  $values = @($Items) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
  if ($values.Count -eq 0) { return "- none" }
  return ($values | ForEach-Object { "- $_" }) -join "`n"
}

$result = Invoke-SkyBridgeApi -Method GET -Path "/v1/goals/$([uri]::EscapeDataString($GoalId))" -ApiBase $ApiBase
$goal = $result.goal
$markdown = @"
# $($goal.title)

goal_id: $($goal.goal_id)
project_id: $($goal.project_id)
status: $($goal.status)
source: $($goal.source)
priority: $($goal.priority)
risk: $($goal.risk)
dedupe_key: $($goal.dedupe_key)

## Summary
$($goal.summary)

## Acceptance Criteria
$(Convert-ArrayToBullets $goal.acceptance_criteria)

## Evidence Requirements
$(Convert-ArrayToBullets $goal.evidence_requirements)

## Evidence Summary
$($goal.evidence_summary.summary)

## Task Summary
Total: $($goal.task_summary.total)
Completed: $($goal.task_summary.completed)
Failed: $($goal.task_summary.failed)
Blocked: $($goal.task_summary.blocked)
Evidence: $($goal.task_summary.evidence_count)
"@

if ($OutFile) {
  Set-Content -LiteralPath $OutFile -Value $markdown -Encoding UTF8
}

if ($Json) {
  @{
    ok = $true
    goal_id = $goal.goal_id
    out_file = $OutFile
    markdown = $(if ($OutFile) { $null } else { $markdown })
    raw_prompts_included = $false
    secrets_included = $false
  } | ConvertTo-Json -Depth 10 -Compress
} else {
  if ($OutFile) { [pscustomobject]@{ GoalId = $goal.goal_id; OutFile = $OutFile; SecretsIncluded = $false } | Format-List }
  else { $markdown }
}
