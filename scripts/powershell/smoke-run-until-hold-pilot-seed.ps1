[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\run-until-hold-pilot-seed-smoke"
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
    -File .\scripts\powershell\skybridge-seed-run-until-hold-pilot-tasks.ps1 `
    -FixtureTasksFile $tasksPath `
    -FixtureStateDir $stateDir `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "seed script failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.run_until_hold_pilot_seed.v1") { throw "Unexpected seed schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  return $result
}

function New-PilotTask {
  param([int]$Index, [string]$Status = "queued", [string[]]$AllowedPaths)
  $suffix = "{0:D3}" -f $Index
  if (-not $AllowedPaths) { $AllowedPaths = @("docs/operations/RUN_UNTIL_HOLD_PILOT_$suffix.md") }
  [pscustomobject]@{
    task_id = "run-until-hold-pilot-docs-$suffix"
    project_id = "skybridge-agent-hub"
    title = "Goal 321 pilot $suffix"
    status = $Status
    risk = "low"
    task_type = "docs"
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($AllowedPaths)
    hygiene_metadata = [pscustomobject]@{ bounded_loop_pilot = $true; allowed_worker_id = "jerry-win-local-01" }
    token_printed = $false
  }
}

$preview = Invoke-Seed -Name "preview-empty" -Tasks @() -Extra @("-Preview")
if ($preview.mode -ne "preview") { throw "Preview mode mismatch." }
if (@($preview.would_create).Count -ne 2) { throw "Preview should would_create exactly 2 tasks." }
if (@($preview.created_tasks).Count -ne 0) { throw "Preview created tasks." }

$missingConfirm = Invoke-Seed -Name "apply-missing-confirm" -Tasks @() -Extra @("-Apply")
Assert-False $missingConfirm.ok "apply missing confirmation ok"
if (@($missingConfirm.blockers) -notcontains "confirmation_required") { throw "Expected confirmation_required." }

$apply = Invoke-Seed -Name "apply-confirmed" -Tasks @() -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_BOUNDED_RUN_UNTIL_HOLD_PILOT_TASKS")
Assert-True $apply.ok "seed apply ok"
if (@($apply.created_tasks).Count -ne 2) { throw "Seed apply should create exactly 2 tasks." }
if (@($apply.created_tasks | ForEach-Object { $_.task_id }) -notcontains "run-until-hold-pilot-docs-001") { throw "Missing pilot 001." }
if (@($apply.created_tasks | ForEach-Object { $_.task_id }) -notcontains "run-until-hold-pilot-docs-002") { throw "Missing pilot 002." }

$existing = Invoke-Seed -Name "existing-safe" -Tasks @((New-PilotTask -Index 1), (New-PilotTask -Index 2)) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_BOUNDED_RUN_UNTIL_HOLD_PILOT_TASKS")
Assert-True $existing.ok "existing safe ok"
if (@($existing.created_tasks | Where-Object { $_.status -eq "existing_safe_pilot_task" }).Count -ne 2) { throw "Expected existing safe tasks." }

$unsafe = Invoke-Seed -Name "existing-unsafe" -Tasks @((New-PilotTask -Index 1 -AllowedPaths @("deploy/docker-compose.yml"))) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_SEED_BOUNDED_RUN_UNTIL_HOLD_PILOT_TASKS")
Assert-False $unsafe.ok "unsafe existing ok"
if (@($unsafe.blockers | Where-Object { $_ -like "existing_pilot_task_not_safe:*" }).Count -lt 1) { throw "Expected unsafe existing blocker." }

$summary = [pscustomobject]@{
  ok = $true
  smoke = "run-until-hold-pilot-seed"
  scenarios = @(
    "seed_preview_creates_no_tasks",
    "seed_apply_requires_confirmation",
    "seed_creates_exactly_2_safe_tasks",
    "existing_safe_batch_reported",
    "existing_unsafe_fails_closed"
  )
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "run-until-hold-pilot-seed" }
