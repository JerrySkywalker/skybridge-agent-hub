[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tmpRoot = Join-Path $RepoRoot ".agent\tmp\campaign-task-compiler-smoke"
New-Item -ItemType Directory -Force -Path $tmpRoot | Out-Null

function Write-Fixture {
  param([string]$Name, $Value)
  $path = Join-Path $tmpRoot $Name
  $Value | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding UTF8
  $path
}

function Invoke-Compiler {
  param([string]$Name, $Campaign, [object[]]$ExistingTasks = @(), [string[]]$Extra = @())
  $campaignPath = Write-Fixture "$Name-campaign.json" $Campaign
  $tasksPath = Write-Fixture "$Name-tasks.json" ([pscustomobject]@{ tasks = @($ExistingTasks) })
  $stateDir = Join-Path $tmpRoot "$Name-state"
  $raw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\powershell\skybridge-compile-campaign-tasks.ps1 `
    -CampaignFile $campaignPath `
    -FixtureTasksFile $tasksPath `
    -FixtureStateDir $stateDir `
    @Extra `
    -Json
  if ($LASTEXITCODE -ne 0) { throw "campaign compiler failed for $Name." }
  $text = (($raw | Out-String).Trim())
  Assert-NoUnsafeText $text
  $result = $text | ConvertFrom-Json
  if ($result.schema -ne "skybridge.campaign_task_compiler.v1") { throw "Unexpected compiler schema for $Name." }
  Assert-False $result.token_printed "$Name token_printed"
  Assert-False $result.forbidden_actions.old_task_claimed "$Name old_task_claimed"
  Assert-False $result.forbidden_actions.old_task_requeued "$Name old_task_requeued"
  Assert-False $result.forbidden_actions.project_control_unpaused "$Name project_control_unpaused"
  return $result
}

function New-Campaign {
  param([object[]]$Tasks)
  [pscustomobject]@{
    campaign_id = "campaign-policy-compiler-pilot-001"
    title = "Improve bounded operator documentation"
    tasks = @($Tasks)
  }
}

function New-Item {
  param(
    [string]$Title,
    [string]$Body,
    [string[]]$AllowedPaths,
    [string]$TaskType = "docs",
    [string]$Risk = "low",
    [string[]]$DependsOn = @()
  )
  [pscustomobject]@{
    title = $Title
    body = $Body
    task_type = $TaskType
    risk = $Risk
    allowed_paths = @($AllowedPaths)
    depends_on = @($DependsOn)
    required_capabilities = @("codex", "docs", "windows")
  }
}

function New-ExistingTask {
  param([string]$TaskId, [string]$Status = "queued", [string[]]$AllowedPaths = @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"))
  [pscustomobject]@{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    campaign_id = "campaign-policy-compiler-pilot-001"
    title = "Existing fixture"
    status = $Status
    risk = "low"
    task_type = "docs"
    allowed_paths = @($AllowedPaths)
    hygiene_metadata = [pscustomobject]@{ campaign_id = "campaign-policy-compiler-pilot-001"; campaign_task_compiler_pilot = $true; bounded_loop_pilot = $true; allowed_worker_id = "jerry-win-local-01" }
    token_printed = $false
  }
}

$safeCampaign = New-Campaign @(
  (New-Item -Title "Stop reasons note" -Body "Add a short note describing bounded stop reasons." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md")),
  (New-Item -Title "Safety rules note" -Body "Add a short note describing compiler safety rules." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md") -DependsOn @("campaign-policy-compiler-pilot-docs-001"))
)

$preview = Invoke-Compiler -Name "safe-preview" -Campaign $safeCampaign -Extra @("-Preview")
Assert-True $preview.ok "safe preview ok"
if ($preview.generated_task_count -ne 2) { throw "Safe preview should generate two tasks." }
Assert-True $preview.would_create_tasks "safe preview would create"
if (@($preview.rejected_items).Count -ne 0) { throw "Safe preview should not reject items." }
if (@($preview.dependency_order)[0] -ne "campaign-policy-compiler-pilot-docs-001") { throw "Dependency order did not preserve first task." }

$missingConfirm = Invoke-Compiler -Name "missing-confirm" -Campaign $safeCampaign -Extra @("-Apply")
Assert-False $missingConfirm.ok "missing confirmation ok"
if (@($missingConfirm.blockers) -notcontains "confirmation_required") { throw "Apply confirmation blocker missing." }

$apply = Invoke-Compiler -Name "safe-apply" -Campaign $safeCampaign -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_COMPILE_SAFE_CAMPAIGN_TASKS_ONLY")
Assert-True $apply.ok "safe apply ok"
if (@($apply.created_tasks).Count -ne 2) { throw "Safe apply should create exactly two tasks." }

foreach ($case in @(
  @{ name = "unsafe-deploy"; body = "Add a production deploy step."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-secrets"; body = "Document secret rotation."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-server-root"; body = "Change server-root config."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-openresty"; body = "Modify OpenResty."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-authelia"; body = "Modify Authelia."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-dns"; body = "Change DNS."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-cloudflare"; body = "Change Cloudflare."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "unsafe-gh-settings"; body = "Change GitHub settings."; path = "docs/operations/CAMPAIGN_COMPILER_PILOT_001.md"; reason = "unsafe_requested_surface" },
  @{ name = "broad-path"; body = "Add a safe note."; path = "docs/operations/*.md"; reason = "unsafe_allowed_path" },
  @{ name = "missing-path"; body = "Add a safe note."; path = $null; reason = "missing_allowed_paths" }
)) {
  $paths = if ($case.path) { @($case.path) } else { @() }
  $campaign = New-Campaign @((New-Item -Title $case.name -Body $case.body -AllowedPaths $paths))
  $result = Invoke-Compiler -Name $case.name -Campaign $campaign -Extra @("-Preview")
  Assert-False $result.ok "$($case.name) ok"
  if (@($result.rejected_items.reasons) -notcontains $case.reason) { throw "$($case.name) did not report $($case.reason)." }
}

$cycleCampaign = New-Campaign @(
  (New-Item -Title "Cycle A" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md") -DependsOn @("campaign-policy-compiler-pilot-docs-002")),
  (New-Item -Title "Cycle B" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md") -DependsOn @("campaign-policy-compiler-pilot-docs-001"))
)
$cycle = Invoke-Compiler -Name "cycle" -Campaign $cycleCampaign -Extra @("-Preview")
Assert-False $cycle.ok "cycle ok"
if (@($cycle.blockers) -notcontains "dependency_cycle") { throw "Dependency cycle blocker missing." }

$tooMany = New-Campaign @(
  (New-Item -Title "One" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md")),
  (New-Item -Title "Two" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md")),
  (New-Item -Title "Three" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_003.md")),
  (New-Item -Title "Four" -Body "Add a safe note." -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_004.md"))
)
$tooManyResult = Invoke-Compiler -Name "too-many" -Campaign $tooMany -Extra @("-Preview")
Assert-False $tooManyResult.ok "too many ok"
if (@($tooManyResult.blockers) -notcontains "more_than_3_generated_tasks") { throw "More-than-3 blocker missing." }

$collision = Invoke-Compiler -Name "collision" -Campaign $safeCampaign -ExistingTasks @((New-ExistingTask -TaskId "campaign-policy-compiler-pilot-docs-001" -Status "failed")) -Extra @("-Preview")
Assert-False $collision.ok "collision ok"
if (@($collision.rejected_items.reasons) -notcontains "generated_task_id_collision_with_old_residue") { throw "Old residue collision rejection missing." }

$completedNoop = Invoke-Compiler -Name "completed-noop" -Campaign $safeCampaign -ExistingTasks @(
  (New-ExistingTask -TaskId "campaign-policy-compiler-pilot-docs-001" -Status "completed"),
  (New-ExistingTask -TaskId "campaign-policy-compiler-pilot-docs-002" -Status "completed" -AllowedPaths @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md"))
) -Extra @("-Apply", "-Confirm", "I_UNDERSTAND_COMPILE_SAFE_CAMPAIGN_TASKS_ONLY")
Assert-True $completedNoop.ok "completed noop ok"
if (@($completedNoop.created_tasks | Where-Object { $_.status -ne "existing_completed_generated_task" }).Count -ne 0) { throw "Completed generated tasks should be terminal no-op." }

$boundedTasksFile = Join-Path $tmpRoot "safe-apply-state\compiled-campaign-tasks.json"
$workersPath = Write-Fixture "workers.json" ([pscustomobject]@{ workers = @([pscustomobject]@{ worker_id = "jerry-win-local-01"; status = "online"; enabled = $true; capabilities = @("codex", "docs", "windows"); token_printed = $false }) })
$hygienePath = Write-Fixture "hygiene.json" ([pscustomobject]@{ unsafe_to_requeue_candidates = @([pscustomobject]@{ task_id = "old-failed-001" }); archive_or_keep_blocked_candidates = @(); token_printed = $false })
$gatePath = Write-Fixture "gate.json" ([pscustomobject]@{ project_control_state = "paused"; allowed_preview_only = $true; allowed_execution = $false; token_printed = $false })
$boundedRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-run-until-hold-bounded.ps1 `
  -CampaignId "campaign-policy-compiler-pilot-001" `
  -FixtureTasksFile $boundedTasksFile `
  -FixtureWorkersFile $workersPath `
  -FixtureHygieneFile $hygienePath `
  -FixtureSecondGateFile $gatePath `
  -FixtureStateDir (Join-Path $tmpRoot "bounded-state") `
  -Preview `
  -MaxTasks 2 `
  -Json
$boundedText = (($boundedRaw | Out-String).Trim())
Assert-NoUnsafeText $boundedText
$boundedPreview = $boundedText | ConvertFrom-Json
if (@($boundedPreview.selected_candidates).Count -ne 2) { throw "Bounded preview should select generated campaign tasks." }
Assert-False $boundedPreview.forbidden_actions.old_task_claimed "bounded preview old claimed"

$boundedApplyRaw = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\powershell\skybridge-run-until-hold-bounded.ps1 `
  -CampaignId "campaign-policy-compiler-pilot-001" `
  -FixtureTasksFile $boundedTasksFile `
  -FixtureWorkersFile $workersPath `
  -FixtureHygieneFile $hygienePath `
  -FixtureSecondGateFile $gatePath `
  -FixtureStateDir (Join-Path $tmpRoot "bounded-apply-state") `
  -Apply `
  -Confirm "I_UNDERSTAND_BOUNDED_RUN_UNTIL_HOLD_MAX_2_SAFE_TASKS" `
  -MaxTasks 2 `
  -FixtureCodexSuccess `
  -Json
$boundedApplyText = (($boundedApplyRaw | Out-String).Trim())
Assert-NoUnsafeText $boundedApplyText
$boundedApply = $boundedApplyText | ConvertFrom-Json
Assert-True $boundedApply.ok "bounded apply ok"
if ($boundedApply.executed_task_count -ne 2) { throw "Bounded apply should execute at most MaxTasks generated campaign tasks." }
Assert-False $boundedApply.forbidden_actions.recursive_run_until_hold "bounded apply recursion"
Assert-False $boundedApply.project_control.project_control_unpaused "bounded apply project control"

$summary = [pscustomobject]@{
  ok = $true
  smoke = "campaign-task-compiler"
  scenarios = @(
    "safe_campaign_preview_generates_2_tasks",
    "safe_campaign_apply_requires_confirmation",
    "safe_campaign_apply_creates_exact_deterministic_tasks",
    "unsafe_deploy_request_rejected",
    "unsafe_secrets_request_rejected",
    "unsafe_server_root_request_rejected",
    "unsafe_openresty_authelia_dns_cloudflare_github_settings_rejected",
    "broad_allowed_paths_rejected",
    "missing_allowed_paths_rejected",
    "dependency_cycle_rejected",
    "more_than_3_generated_tasks_rejected",
    "id_collision_with_old_residue_rejected",
    "completed_generated_task_terminal_noop",
    "bounded_preview_selects_generated_campaign_tasks",
    "bounded_apply_executes_at_most_MaxTasks",
    "no_old_failed_blocked_completed_task_selected",
    "project_control_remains_paused",
    "no_daemon_no_recursion",
    "token_printed_false"
  )
  token_printed = $false
}

if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { Complete-Smoke "campaign-task-compiler" }
