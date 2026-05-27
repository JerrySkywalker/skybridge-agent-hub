[CmdletBinding()]
param(
  [string]$ApiBase = $(if ($env:SKYBRIDGE_API_BASE) { $env:SKYBRIDGE_API_BASE } else { "http://127.0.0.1:8787" }),
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$GoalId,
  [string]$GoalTitle,
  [string]$TaskId,
  [string]$TaskTitle,
  [string]$TaskBody,
  [string]$TaskBodyFile,
  [ValidateSet("low", "medium", "high")]
  [string]$Risk = "low",
  [string[]]$RequiredCapabilities = @("codex"),
  [string]$Source = "manual",
  [string]$TokenEnvVar,
  [string]$TokenFile,
  [switch]$EnsureProject,
  [switch]$EnsureGoal,
  [switch]$DryRun,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputFile
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

function New-SubmitApiConfig {
  $authMode = "none"
  if (-not [string]::IsNullOrWhiteSpace($TokenEnvVar) -or -not [string]::IsNullOrWhiteSpace($TokenFile)) {
    $authMode = "bearer_token"
  }
  [pscustomobject]@{
    api_base = $ApiBase
    project_id = $ProjectId
    auth_mode = $authMode
    token_env_var = $TokenEnvVar
    token_file = $TokenFile
  }
}

function Invoke-SubmitApi {
  param([string]$Method, [string]$Path, $Body = $null)
  Invoke-SkyBridgeApi -Method $Method -Path $Path -ApiBase $ApiBase -Body $Body -Config $script:Config -TimeoutSeconds 10
}

function Test-SubmitResourceExists {
  param([string]$Path)
  try {
    Invoke-SubmitApi -Method GET -Path $Path | Out-Null
    return $true
  } catch {
    return $false
  }
}

function New-SubmitSlug {
  param([string]$Prefix, [string]$Text)
  $slug = ($Text.ToLowerInvariant() -replace "[^a-z0-9]+", "-" -replace "^-|-$", "")
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = (Get-Date -Format "yyyyMMddHHmmss") }
  return "$Prefix-$slug"
}

function Write-SubmitResult {
  param($Result)
  if (-not [string]::IsNullOrWhiteSpace($OutputFile)) {
    $outputDir = Split-Path -Parent $OutputFile
    if (-not [string]::IsNullOrWhiteSpace($outputDir)) {
      New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $Result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputFile -Encoding UTF8
  }
  if ($Json) {
    $Result | ConvertTo-Json -Depth 30 -Compress
    return
  }
  "Project: $($Result.project.id) $($Result.project.action)"
  "Goal:    $($Result.goal.id) $($Result.goal.action)"
  "Task:    $($Result.task.id) $($Result.task.action)"
  "Mode:    $($Result.mode)"
  "Next:    $($Result.next_command)"
  "TokenPrinted: false"
}

if ([string]::IsNullOrWhiteSpace($TaskTitle)) { throw "skybridge-submit requires -TaskTitle." }
if ([string]::IsNullOrWhiteSpace($GoalTitle) -and [string]::IsNullOrWhiteSpace($GoalId)) { throw "skybridge-submit requires -GoalTitle or -GoalId." }
if (-not [string]::IsNullOrWhiteSpace($TaskBodyFile)) {
  if (-not (Test-Path -LiteralPath $TaskBodyFile -PathType Leaf)) { throw "Task body file not found: $TaskBodyFile" }
  $TaskBody = Get-Content -Raw -LiteralPath $TaskBodyFile
}
if ([string]::IsNullOrWhiteSpace($TaskBody)) { $TaskBody = $TaskTitle }
if ([string]::IsNullOrWhiteSpace($GoalTitle)) { $GoalTitle = $GoalId }
if ([string]::IsNullOrWhiteSpace($GoalId)) { $GoalId = New-SubmitSlug -Prefix "goal" -Text $GoalTitle }
if ([string]::IsNullOrWhiteSpace($TaskId)) { $TaskId = New-SubmitSlug -Prefix "task" -Text $TaskTitle }

$script:Config = New-SubmitApiConfig
if ($script:Config.auth_mode -eq "bearer_token" -and [string]::IsNullOrWhiteSpace((Get-SkyBridgeWorkerToken -Config $script:Config))) {
  throw "SkyBridge worker token is required by the selected TokenEnvVar or TokenFile."
}

$effectiveDryRun = $DryRun -or -not $Apply
$projectAction = "skipped"
$goalAction = "skipped"
$taskAction = "skipped"

$projectExists = Test-SubmitResourceExists -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))"
if ($projectExists) {
  $projectAction = "existing"
} elseif ($EnsureProject) {
  $projectAction = if ($effectiveDryRun) { "would_create" } else { "created" }
  if (-not $effectiveDryRun) {
    Invoke-SubmitApi -Method POST -Path "/v1/projects" -Body @{ project_id = $ProjectId; name = $ProjectId } | Out-Null
  }
} else {
  throw "Project '$ProjectId' does not exist. Use -EnsureProject to create it."
}

$goalExists = Test-SubmitResourceExists -Path "/v1/goals/$([uri]::EscapeDataString($GoalId))"
if ($goalExists) {
  $goalAction = "existing"
} elseif ($EnsureGoal) {
  $goalAction = if ($effectiveDryRun) { "would_create" } else { "created" }
  if (-not $effectiveDryRun) {
    Invoke-SubmitApi -Method POST -Path "/v1/projects/$([uri]::EscapeDataString($ProjectId))/goals" -Body @{
      goal_id = $GoalId
      title = $GoalTitle
      summary = $TaskBody
      source = $Source
      risk = $Risk
      status = "ready"
      acceptance_criteria = @("Task is completed with evidence.")
      evidence_requirements = @("Worker result and validation summary are recorded.")
    } | Out-Null
  }
} else {
  throw "Goal '$GoalId' does not exist. Use -EnsureGoal to create it."
}

$taskExists = Test-SubmitResourceExists -Path "/v1/tasks/$([uri]::EscapeDataString($TaskId))"
if ($taskExists) {
  $taskAction = "existing"
} else {
  $taskAction = if ($effectiveDryRun) { "would_create" } else { "created" }
  if (-not $effectiveDryRun) {
    Invoke-SubmitApi -Method POST -Path "/v1/tasks" -Body @{
      task_id = $TaskId
      project_id = $ProjectId
      goal_id = $GoalId
      title = $TaskTitle
      body = $TaskBody
      prompt_summary = $TaskBody
      risk = $Risk
      source = $Source
      required_capabilities = @($RequiredCapabilities)
    } | Out-Null
  }
}

Write-SubmitResult ([pscustomobject]@{
  ok = $true
  mode = if ($effectiveDryRun) { "dry-run" } else { "apply" }
  api_base = $ApiBase
  token_printed = $false
  project = [pscustomobject]@{ id = $ProjectId; action = $projectAction }
  goal = [pscustomobject]@{ id = $GoalId; title = $GoalTitle; action = $goalAction }
  task = [pscustomobject]@{ id = $TaskId; title = $TaskTitle; action = $taskAction; required_capabilities = @($RequiredCapabilities); risk = $Risk; source = $Source }
  next_command = "pwsh -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-run-once.ps1 -ProjectId $ProjectId -GoalId $GoalId -TaskId $TaskId -NoSubmit -Apply"
})
