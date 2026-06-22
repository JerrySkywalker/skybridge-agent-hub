[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\start-one-pilot-seed-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Invoke-Seed {
  param([string]$Name, [object[]]$Tasks, [string[]]$Extra = @())
  $tasksPath = Write-Fixture "$Name-tasks.json" ([pscustomobject]@{ tasks = @($Tasks) })
  $stateDir = Join-Path $tmpRoot "$Name-state"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-seed-start-one-pilot-task.ps1 `
    -FixtureTasksFile $tasksPath `
    -FixtureStateDir $stateDir `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "seed script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.start_one_pilot_seed.v1") { throw "Unexpected seed schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  return $result
}

function New-PilotTask {
  param([string]$Status = "queued", [string]$Risk = "low", [string[]]$AllowedPaths = @("docs/operations/START_ONE_APPLY_PILOT.md"))
  [pscustomobject]@{
    task_id = "start-one-apply-pilot-docs-001"
    project_id = "skybridge-agent-hub"
    title = "Goal 319 safe start-one apply pilot docs task"
    status = $Status
    risk = $Risk
    task_type = "docs"
    source = "manual"
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($AllowedPaths)
    token_printed = $false
  }
}

$preview = Invoke-Seed -Name "preview-empty" -Tasks @() -Extra @("-Preview")
if ($preview.mode -ne "preview") { throw "Seed default/preview mode mismatch." }
Assert-True $preview.would_create_task "preview would_create_task"
if ($null -ne $preview.created_task) { throw "Preview must not create a task." }

$missingConfirm = Invoke-Seed -Name "apply-missing-confirm" -Tasks @() -Extra @("-Apply")
Assert-False $missingConfirm.ok "apply missing confirmation ok"
if (@($missingConfirm.blockers) -notcontains "confirmation_required") { throw "Expected confirmation_required." }

$apply = Invoke-Seed -Name "apply-confirmed" -Tasks @() -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK")
Assert-True $apply.ok "seed apply ok"
if ($apply.created_task.task_id -ne "start-one-apply-pilot-docs-001") { throw "Unexpected created task id." }
if (@($apply.created_task.allowed_paths) -ne "docs/operations/START_ONE_APPLY_PILOT.md") { throw "Unexpected allowed path." }

$existing = Invoke-Seed -Name "existing-safe" -Tasks @((New-PilotTask)) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK")
if ($existing.status -ne "existing_safe_pilot_task") { throw "Expected existing safe pilot task." }
Assert-False $existing.would_create_task "existing would_create_task"

$existingCompleted = Invoke-Seed -Name "existing-completed" -Tasks @((New-PilotTask -Status "completed")) -Extra @("-Preview")
if ($existingCompleted.status -ne "existing_completed_pilot_task") { throw "Expected existing completed pilot task." }
Assert-False $existingCompleted.would_create_task "existing completed would_create_task"

$unsafe = Invoke-Seed -Name "existing-unsafe" -Tasks @((New-PilotTask -AllowedPaths @("deploy/docker-compose.yml"))) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_ONE_SAFE_START_ONE_PILOT_TASK")
Assert-False $unsafe.ok "unsafe existing ok"
if (@($unsafe.blockers) -notcontains "existing_pilot_task_not_safe") { throw "Expected existing_pilot_task_not_safe." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "start-one-pilot-seed"
  scenarios = @(
    "seed_preview_creates_no_task",
    "seed_apply_requires_confirmation",
    "seed_apply_only_creates_safe_pilot_task_fixture",
    "existing_safe_reported",
    "existing_completed_reported",
    "existing_unsafe_fails_closed"
  )
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8 -Compress
} else {
  Complete-Smoke "start-one-pilot-seed"
}
