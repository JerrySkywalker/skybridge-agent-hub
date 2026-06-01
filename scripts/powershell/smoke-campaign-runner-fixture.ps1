[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Scenario
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $repoRoot
$goalPack = "goals/dev-queue-189-200"
$runnerRoot = Join-Path ".agent" "campaign-runners"

function Clear-RunnerState {
  if (Test-Path -LiteralPath $runnerRoot) {
    Remove-Item -LiteralPath $runnerRoot -Recurse -Force
  }
}

function Invoke-RunnerJson {
  param([string[]]$Arguments)
  $output = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File .\scripts\powershell\skybridge-campaign.ps1 @Arguments -Json 2>&1
  if ($LASTEXITCODE -ne 0) { throw "skybridge-campaign failed for $Scenario`: $($output -join "`n")" }
  return ($output | ConvertFrom-Json)
}

function New-Lock {
  param([string]$Status = "active", [int]$Minutes = 30, [string]$Owner = "fixture")
  $dir = Join-Path $runnerRoot "locks"
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $path = Join-Path $dir "skybridge-agent-hub__dev-queue-189-200.lock.json"
  @{
    schema = "skybridge.campaign_runner_lock.v1"
    campaign_lock_id = "lock_fixture"
    campaign_id = "dev-queue-189-200"
    project_id = "skybridge-agent-hub"
    lock_owner = $Owner
    lock_status = $Status
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    heartbeat_at = (Get-Date).ToUniversalTime().ToString("o")
    expires_at = if ($Minutes -lt 0) { "2000-01-01T00:00:00Z" } else { "2099-01-01T00:00:00Z" }
    release_reason = $null
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

try {
  Clear-RunnerState
  switch ($Scenario) {
    "run-next" {
      $result = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-MaxSteps", "12", "-MaxTasks", "12")
      Assert-True (@($result.planned_actions).Count -eq 1) "run-next should plan exactly one step."
      Assert-True ($result.stop_reason -eq "run_next_completed") "run-next should stop after one step."
    }
    "run-until-hold" {
      $result = Invoke-RunnerJson @("run-until-hold", "-GoalPackDir", $goalPack, "-DryRun", "-MaxSteps", "12", "-MaxTasks", "12")
      Assert-True ($result.runner_state.runner_status -eq "held") "Expected held status."
      Assert-True ($result.stop_reason -match "human_approval_required") "Expected human approval hold."
    }
    "run-until-complete" {
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-MaxSteps", "12", "-MaxTasks", "12")
      Assert-True (@($result.planned_actions).Count -eq 12) "Expected all 12 planned steps."
      Assert-True ($result.runner_state.runner_status -eq "completed") "Expected completed runner."
    }
    "max-steps" {
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-MaxSteps", "2", "-MaxTasks", "12")
      Assert-True (@($result.planned_actions).Count -eq 2) "Expected two planned steps."
      Assert-True ($result.stop_reason -eq "max_steps_reached") "Expected max_steps_reached."
    }
    "max-tasks" {
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-MaxSteps", "12", "-MaxTasks", "2")
      Assert-True (@($result.planned_actions).Count -eq 2) "Expected two planned tasks."
      Assert-True ($result.stop_reason -eq "max_tasks_reached") "Expected max_tasks_reached."
    }
    "max-runtime" {
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", "0")
      Assert-True ($result.stop_reason -eq "max_runtime_reached") "Expected max_runtime_reached."
    }
    "delegated-approval" {
      $result = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "delegated fixture", "-MaxSteps", "1", "-MaxTasks", "1")
      Assert-True (@($result.planned_actions[0].blockers).Count -eq 0) "Delegated approval should satisfy human approval."
      Assert-True (-not [string]::IsNullOrWhiteSpace([string]$result.approval_scope.scope_hash)) "Expected approval scope hash."
    }
    "hard-veto" {
      $result = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture approval", "-AllowServerDeploy")
      Assert-True (@($result.hard_blockers) -contains "allow_server_deploy_not_supported_by_campaign_runner") "Expected hard veto."
    }
    "resume" {
      Invoke-RunnerJson @("run-until-hold", "-GoalPackDir", $goalPack, "-DryRun") | Out-Null
      $result = Invoke-RunnerJson @("resume", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture resume", "-MaxSteps", "12", "-MaxTasks", "12")
      Assert-True ($result.runner_state.steps_attempted -ge 1) "Expected resumed state."
      Assert-True (@($result.planned_actions | Select-Object -ExpandProperty goal_id) -notcontains "super-189-ci-guardian-pr-finalizer-hardening") "Resume should not duplicate first attempted step."
    }
    "report-json" {
      Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun") | Out-Null
      $result = Invoke-RunnerJson @("runner-report", "-GoalPackDir", $goalPack, "-DryRun")
      Assert-True ($result.token_printed -eq $false) "Expected token_printed=false."
      Assert-True ($result.report.markdown -match "Campaign Runner Report") "Expected markdown report."
    }
    "lock" {
      New-Lock -Status "active" | Out-Null
      $result = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture")
      Assert-True (@($result.hard_blockers) -contains "active_runner_lock") "Expected active runner lock blocker."
    }
    "self-lock" {
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-Apply", "-HumanApproved", "-HumanApprovalReason", "fixture", "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", "0")
      Assert-True (@($result.hard_blockers) -notcontains "active_runner_lock") "Self-owned active runner lock must not block the runner."
      Assert-True ($result.stop_reason -eq "max_runtime_reached") "Expected bounded apply regression to stop before step execution."
      Assert-True (@($result.planned_actions).Count -eq 0) "Bounded apply regression must not plan or execute steps."
      Assert-True ($result.runner_lock.lock_owner -eq $result.runner_state.runner_id) "Expected lock owner to match current runner."
      $status = Invoke-RunnerJson @("runner-status", "-CampaignId", "dev-queue-189-200", "-GoalPackDir", $goalPack)
      Assert-True ($status.runner_lock_status -eq "released") "Self-owned apply lock should be released on stop."
    }
    "foreign-active-lock" {
      New-Lock -Status "active" -Owner "foreign-runner" | Out-Null
      $result = Invoke-RunnerJson @("run-until-complete", "-GoalPackDir", $goalPack, "-Apply", "-HumanApproved", "-HumanApprovalReason", "fixture", "-MaxSteps", "12", "-MaxTasks", "12", "-MaxRuntimeMinutes", "0")
      Assert-True (@($result.hard_blockers) -contains "active_runner_lock") "Expected foreign active runner lock blocker."
      Assert-True ($result.stop_reason -eq "active_runner_lock") "Expected active_runner_lock stop reason."
      Assert-True ($result.runner_lock.lock_owner -eq "foreign-runner") "Runner must not replace a foreign lock."
      $status = Invoke-RunnerJson @("runner-status", "-CampaignId", "dev-queue-189-200", "-GoalPackDir", $goalPack)
      Assert-True ($status.runner_lock_status -eq "active") "Runner must not release a foreign lock."
    }
    "stale-lock" {
      New-Lock -Status "active" -Minutes -1 | Out-Null
      $result = Invoke-RunnerJson @("runner-status", "-GoalPackDir", $goalPack)
      Assert-True ($result.runner_lock_status -eq "stale") "Expected stale lock."
      $run = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun", "-HumanApproved", "-HumanApprovalReason", "fixture")
      Assert-True (@($run.hard_blockers) -contains "stale_runner_lock") "Expected stale runner lock blocker."
    }
    "unlock-requires-apply" {
      New-Lock -Status "active" | Out-Null
      $result = Invoke-RunnerJson @("runner-unlock", "-CampaignId", "dev-queue-189-200", "-Reason", "fixture", "-DryRun")
      Assert-True ($result.would_unlock -eq $true) "Expected dry-run unlock preview."
      $status = Invoke-RunnerJson @("runner-status", "-CampaignId", "dev-queue-189-200", "-GoalPackDir", $goalPack)
      Assert-True ($status.runner_lock_status -eq "active") "Dry-run unlock must not release lock."
    }
    "single-active" {
      New-Lock -Status "active" | Out-Null
      $result = Invoke-RunnerJson @("runner-status", "-CampaignId", "dev-queue-189-200", "-GoalPackDir", $goalPack)
      Assert-True ($result.runner_lock_status -eq "active") "Expected one active lock to be visible."
    }
    "json-clean" {
      $result = Invoke-RunnerJson @("run-next", "-GoalPackDir", $goalPack, "-DryRun")
      $text = $result | ConvertTo-Json -Depth 80
      Assert-True ($text -notmatch "(?i)(sk-[A-Za-z0-9_-]{20,}|worker-token|hermes_api_key|private key)") "Runner JSON should not contain secrets."
    }
    default { throw "Unknown campaign runner fixture scenario: $Scenario" }
  }
  [pscustomobject]@{ ok = $true; scenario = $Scenario; token_printed = $false } | ConvertTo-Json -Compress
} finally {
  Clear-RunnerState
}
