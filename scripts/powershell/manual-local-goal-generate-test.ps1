[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$GenerateOne,
  [switch]$Fixture,
  [switch]$UseCodex,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/generated-goals",
  [string]$GoalId = "",
  [string]$Title = "",
  [string]$Objective = "",
  [string]$CampaignId = "",
  [string]$ProjectId = "skybridge-agent-hub",
  [int]$GoalBudgetRemaining = 1,
  [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $GenerateOne) {
  $Preview = $true
}
if (-not $UseCodex -and -not $Fixture) {
  $Fixture = $true
}
if ($UseCodex) {
  $Fixture = $false
}

$command = if ($GenerateOne) { "generate-one" } else { "preview" }
$args = @(
  "-Command", $command,
  "-OutputDir", $OutputDir,
  "-ProjectId", $ProjectId,
  "-GoalBudgetRemaining", ([string]$GoalBudgetRemaining),
  "-Json"
)
if ($Fixture) { $args += "-Fixture" }
if ($UseCodex) { $args += "-UseCodex" }
if ($WriteReport) { $args += "-WriteReport" }
if (-not [string]::IsNullOrWhiteSpace($GoalId)) { $args += @("-GoalId", $GoalId) }
if (-not [string]::IsNullOrWhiteSpace($Title)) { $args += @("-Title", $Title) }
if (-not [string]::IsNullOrWhiteSpace($Objective)) { $args += @("-Objective", $Objective) }
if (-not [string]::IsNullOrWhiteSpace($CampaignId)) { $args += @("-CampaignId", $CampaignId) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-goal-generator.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-local-goal-generator.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.local_goal_generator_manual_test.v1"
  milestone = "M4: Local Codex Goal Markdown Generator Manual Test"
  mode = $result.mode
  action = $command
  generated_markdown_path = $result.generated_goal_path_safe
  generated_metadata_valid = $result.generated_goal_schema_valid
  generated_safety_valid = $result.generated_goal_safety_valid
  human_review_required = $true
  import_allowed = $false
  execution_allowed = $false
  import_performed = $result.import_performed
  approval_performed = $result.approval_performed
  append_performed = $result.append_performed
  task_created = $result.task_created
  task_claimed = $result.task_claimed
  execution_started = $result.execution_started
  worker_loop_started = $result.worker_loop_started
  codex_generation_called = $result.codex_generation_called
  matlab_run_called = $result.matlab_run_called
  hermes_run_called = $result.hermes_run_called
  mcp_run_called = $result.mcp_run_called
  blockers = @($result.blockers)
  warnings = @($result.warnings)
  token_printed = $false
  result = $result
}

if ($Json) {
  $checklist | ConvertTo-Json -Depth 90
} else {
  Write-Host "M4 Manual Test Checklist:"
  Write-Host "- generated markdown path: $($checklist.generated_markdown_path)"
  Write-Host "- metadata valid: $($checklist.generated_metadata_valid)"
  Write-Host "- safety valid: $($checklist.generated_safety_valid)"
  Write-Host "- import_allowed: false"
  Write-Host "- execution_allowed: false"
  Write-Host "- import/append/execute performed: false"
  Write-Host "- token_printed=false"
}
