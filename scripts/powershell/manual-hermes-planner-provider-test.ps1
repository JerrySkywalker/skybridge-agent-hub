[CmdletBinding()]
param(
  [switch]$Status,
  [switch]$Preview,
  [switch]$RunFixture,
  [switch]$LiveStatus,
  [switch]$LivePlan,
  [switch]$ValidateCandidate,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$OutputDir = ".agent/tmp/hermes-planner-provider",
  [string]$Objective = "",
  [string]$CandidatePath = "",
  [string]$ExpectedHash = "",
  [string]$HermesBaseUrl = "",
  [string]$TokenFile = "",
  [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

if (-not $Status -and -not $Preview -and -not $RunFixture -and -not $LiveStatus -and -not $LivePlan -and -not $ValidateCandidate) {
  $Preview = $true
}

$command = "preview"
if ($Status) { $command = "status" }
if ($RunFixture) { $command = "fixture-plan" }
if ($LiveStatus) { $command = "live-status" }
if ($LivePlan) { $command = "live-plan" }
if ($ValidateCandidate) { $command = "validate-candidate" }

$args = @(
  "-Command", $command,
  "-OutputDir", $OutputDir,
  "-Json"
)
if ($WriteReport) { $args += "-WriteReport" }
if (-not [string]::IsNullOrWhiteSpace($Objective)) { $args += @("-Objective", $Objective) }
if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) { $args += @("-CandidatePath", $CandidatePath) }
if (-not [string]::IsNullOrWhiteSpace($ExpectedHash)) { $args += @("-ExpectedHash", $ExpectedHash) }
if (-not [string]::IsNullOrWhiteSpace($HermesBaseUrl)) { $args += @("-HermesBaseUrl", $HermesBaseUrl) }
if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-hermes-planner-provider.ps1") @args
if ($LASTEXITCODE -ne 0) { throw "skybridge-hermes-planner-provider.ps1 failed." }
$result = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.hermes_planner_provider_manual_test.v1"
  milestone = "Hermes Planner Provider Pilot Manual Test"
  action = $command
  provider_role = "planner"
  provider_available = $result.provider_available
  candidate_goal_path_safe = $result.candidate_goal_path_safe
  candidate_goal_hash = $result.candidate_goal_hash
  candidate_validated = $result.candidate_validated
  candidate_approved = $false
  candidate_appended = $false
  task_created = $false
  task_claimed = $false
  execution_started = $false
  branch_created = $false
  pr_created = $false
  merge_performed = $false
  deploy_triggered = $false
  raw_prompt_persisted = $false
  raw_response_persisted = $false
  secrets_persisted = $false
  blockers = @($result.blockers)
  warnings = @($result.warnings)
  token_printed = $false
  result = $result
}

if ($Json) {
  $checklist | ConvertTo-Json -Depth 90
} else {
  Write-Host "Hermes Planner Provider Manual Checklist:"
  Write-Host "- provider role: planner"
  Write-Host "- candidate path: $($checklist.candidate_goal_path_safe)"
  Write-Host "- candidate validated: $($checklist.candidate_validated)"
  Write-Host "- candidate approved: false"
  Write-Host "- candidate appended: false"
  Write-Host "- execution started: false"
  Write-Host "- token_printed=false"
}
