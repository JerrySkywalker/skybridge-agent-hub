[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$TaskId,
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$GoalId,
  [switch]$DryRun,
  [switch]$Json
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-HermesHeaders {
  param([Parameter(Mandatory = $true)][string]$ApiKey)
  return @{ Authorization = "Bearer $ApiKey"; "Content-Type" = "application/json" }
}

function Get-StrictJsonText {
  param($Response)
  if ($Response.output_text) { return [string]$Response.output_text }
  if ($Response.text) { return [string]$Response.text }
  if ($Response.content) { return [string]$Response.content }
  $parts = @()
  foreach ($item in @($Response.output)) {
    foreach ($content in @($item.content)) {
      if ($content.text) { $parts += [string]$content.text }
    }
  }
  if ($parts.Count -gt 0) { return ($parts -join "`n") }
  return ($Response | ConvertTo-Json -Depth 20)
}

function Test-PlannerDecisionSchema {
  param($Decision)
  $allowed = @("continue", "stop", "ask_human", "retry_once", "repair_evidence", "summarize")
  if ($allowed -notcontains [string]$Decision.recommendation) { throw "Invalid evaluation recommendation: $($Decision.recommendation)" }
  if ([string]::IsNullOrWhiteSpace($Decision.reason)) { throw "Evaluation decision missing reason." }
}

function ConvertFrom-StrictPlannerJson {
  param([Parameter(Mandatory = $true)][string]$Text)
  $trimmed = $Text.Trim()
  if ($trimmed -match '```(?:json)?\s*([\s\S]*?)\s*```') { $trimmed = $Matches[1].Trim() }
  $parsed = $trimmed | ConvertFrom-Json
  Test-PlannerDecisionSchema -Decision $parsed
  return $parsed
}

function Invoke-HermesPlanner {
  param([string]$Prompt)
  $loader = Join-Path $PSScriptRoot "load-hermes-env.ps1"
  if (Test-Path -LiteralPath $loader -PathType Leaf) { . $loader }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_BASE)) { throw "HERMES_API_BASE is missing." }
  if ([string]::IsNullOrWhiteSpace($env:HERMES_API_KEY)) { throw "HERMES_API_KEY is missing." }
  $body = @{
    model = if ($env:HERMES_MODEL) { $env:HERMES_MODEL } else { "default" }
    input = $Prompt
    response_format = @{ type = "json_object" }
  }
  return Invoke-RestMethod -Method POST -Uri "$($env:HERMES_API_BASE.TrimEnd('/'))/v1/responses" -Headers (New-HermesHeaders -ApiKey $env:HERMES_API_KEY) -ContentType "application/json" -Body ($body | ConvertTo-Json -Depth 20) -TimeoutSec 120
}

function New-DryRunEvaluationDecision {
  param($Task)
  return [pscustomobject]@{
    recommendation = if ($Task.status -eq "completed") { "continue" } elseif ($Task.status -eq "failed") { "repair_evidence" } else { "summarize" }
    reason = "Dry-run evaluation based on task status $($Task.status)."
  }
}

function Invoke-HermesEvaluation {
  param($Task)
  $summary = @{
    task_id = $Task.task_id
    title = $Task.title
    status = $Task.status
    risk = $Task.risk
    source = $Task.source
    result = $Task.result
    planner_metadata = $Task.planner_metadata
  } | ConvertTo-Json -Depth 12
  $prompt = @"
Return only strict JSON with:
- recommendation: one of continue, stop, ask_human, retry_once, repair_evidence, summarize
- reason: concise advisory rationale

Hermes is advisory only. SkyBridge deterministic policy is final. Do not execute commands.

Task result summary:
$summary
"@
  $response = Invoke-HermesPlanner -Prompt $prompt
  return ConvertFrom-StrictPlannerJson -Text (Get-StrictJsonText -Response $response)
}

$taskResponse = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))" -ApiBase $ApiBase
$task = $taskResponse.task
$decision = if ($DryRun) { New-DryRunEvaluationDecision -Task $task } else { Invoke-HermesEvaluation -Task $task }

$result = [pscustomobject]@{
  ok = $true
  dry_run = [bool]$DryRun
  task_id = $TaskId
  task_status = $task.status
  hermes_recommendation = $decision.recommendation
  policy_decision = "not_evaluated_by_this_script"
  final_decision = "skybridge_policy_required"
  decision = $decision
  hermes_api_key_value_included = $false
}

if ($Json) { $result | ConvertTo-Json -Depth 30 } else { $result | Format-List }
