[CmdletBinding(DefaultParameterSetName = "Preview")]
param(
  [switch]$Json,
  [string]$ApiBase,
  [string]$TokenFile,
  [string]$ProjectId = "skybridge-agent-hub",
  [string]$CampaignFile,
  [string]$CampaignId = "campaign-policy-compiler-pilot-001",
  [Parameter(ParameterSetName = "Preview")][switch]$Preview,
  [Parameter(ParameterSetName = "Apply")][switch]$Apply,
  [string]$Confirm,
  [int]$TimeoutSeconds = 30,
  [string]$FixtureTasksFile,
  [string]$FixtureStateDir
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $RepoRoot
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$Mode = if ($Apply) { "apply" } else { "preview" }
$ConfirmText = "I_UNDERSTAND_COMPILE_SAFE_CAMPAIGN_TASKS_ONLY"
$WorkerId = "jerry-win-local-01"
$TaskPrefix = "campaign-policy-compiler-pilot-docs-"
$AllowedPathPrefix = "docs/operations/CAMPAIGN_COMPILER_PILOT_"
$BlockedPaths = @(
  ".env",
  "secrets/**",
  "deploy/**",
  ".github/settings/**",
  "server-root/**",
  "OpenResty/**",
  "Authelia/**",
  "DNS/**",
  "Cloudflare/**",
  "GitHub settings / branch protection",
  "external-infrastructure/**"
)

function Get-Prop {
  param($Object, [string]$Name, $Default = $null)
  if ($null -eq $Object) { return $Default }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $Default }
  return $prop.Value
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-DefaultCampaign {
  [pscustomobject]@{
    campaign_id = $CampaignId
    title = "Improve bounded operator documentation"
    tasks = @(
      [pscustomobject]@{
        title = "Add bounded run-until-hold stop reason note"
        body = "Add a short note describing bounded run-until-hold stop reasons."
        task_type = "docs"
        risk = "low"
        allowed_paths = @("docs/operations/CAMPAIGN_COMPILER_PILOT_001.md")
        depends_on = @()
      },
      [pscustomobject]@{
        title = "Add campaign compiler safety rules note"
        body = "Add a short note describing campaign compiler task safety rules."
        task_type = "docs"
        risk = "low"
        allowed_paths = @("docs/operations/CAMPAIGN_COMPILER_PILOT_002.md")
        depends_on = @("campaign-policy-compiler-pilot-docs-001")
      }
    )
  }
}

function Get-CampaignPlan {
  if ($CampaignFile) {
    return Read-JsonFile -Path $CampaignFile
  }
  Get-DefaultCampaign
}

function Get-ExistingTasks {
  if ($FixtureTasksFile) {
    $fixture = Read-JsonFile -Path $FixtureTasksFile
    return @((Get-Prop -Object $fixture -Name "tasks" -Default $fixture) | Where-Object { $null -ne $_ })
  }
  if ([string]::IsNullOrWhiteSpace($ApiBase)) { return @() }
  $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
  try {
    $response = Invoke-SkyBridgeApi -Method GET -Path "/v1/tasks?project_id=$([uri]::EscapeDataString($ProjectId))" -ApiBase $ApiBase -Config $config -TimeoutSeconds $TimeoutSeconds
    return @((Get-Prop -Object $response -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
  } catch {
    return @()
  }
}

function Get-AllowedPathForIndex {
  param([int]$Index)
  "$AllowedPathPrefix$("{0:D3}" -f $Index).md"
}

function Get-TaskIdForIndex {
  param([int]$Index)
  "$TaskPrefix$("{0:D3}" -f $Index)"
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return ($Text -match "(?i)\b(deploy|deployment|production|secret|credential|cookie|server-root|openresty|authelia|cloudflare|dns|github settings|branch protection|docker daemon|/opt/skybridge-agent-hub|external infrastructure)\b")
}

function Test-UnsafePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $true }
  $normalized = $Path.Replace("\", "/")
  if ($normalized -match "[*?]") { return $true }
  if ($normalized -match "(?i)(^|/)(\.env|secrets|deploy|server-root|openresty|authelia|dns|cloudflare)(/|$)") { return $true }
  if ($normalized -match "(?i)^\.github/settings/") { return $true }
  if ($normalized -match "(?i)(github-settings|branch-protection|external-infrastructure)") { return $true }
  return $false
}

function Test-DependencyCycle {
  param([array]$Items)
  $ids = @($Items | ForEach-Object { [string]$_.task_id })
  foreach ($item in @($Items)) {
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $stack = @([string]$item.task_id)
    while ($stack.Count -gt 0) {
      $current = [string]$stack[0]
      $stack = @($stack | Select-Object -Skip 1)
      if (-not $seen.Add($current)) { return $true }
      $node = @($Items | Where-Object { [string]$_.task_id -eq $current } | Select-Object -First 1)
      foreach ($dep in @((Get-Prop -Object $node[0] -Name "depends_on" -Default @()))) {
        $depText = [string]$dep
        if ($depText -eq [string]$item.task_id -and $current -ne [string]$item.task_id) { return $true }
        if ($ids -contains $depText) { $stack += $depText }
      }
    }
  }
  return $false
}

function New-GeneratedTask {
  param($Item, [int]$Index)
  $suffix = "{0:D3}" -f $Index
  $taskId = Get-TaskIdForIndex -Index $Index
  $allowedPath = Get-AllowedPathForIndex -Index $Index
  [pscustomobject]@{
    task_id = $taskId
    project_id = $ProjectId
    campaign_id = $CampaignId
    title = "Goal 322 campaign compiler pilot $suffix"
    body = "Update only $allowedPath with the campaign compiler pilot note."
    prompt_summary = "Docs-only campaign compiler pilot limited to $allowedPath."
    status = "queued"
    risk = "low"
    source = "manual"
    task_type = "docs"
    planner_metadata = [pscustomobject]@{
      adapter = "campaign-task-compiler"
      decision = "continue"
      reason = "safe bounded campaign task"
      task_type = "docs"
      allowed_paths = @($allowedPath)
      blocked_paths = @($BlockedPaths)
      validation = @("corepack pnpm smoke:campaign-task-compiler", "corepack pnpm smoke:run-until-hold-bounded")
      expected_files = @($allowedPath)
      source_campaign_id = $CampaignId
      source_campaign_step_id = $taskId
      source_goal_id = "mega-goal-322"
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    required_capabilities = @("codex", "docs", "windows")
    allowed_paths = @($allowedPath)
    blocked_paths = @($BlockedPaths)
    depends_on = @((Get-Prop -Object $Item -Name "depends_on" -Default @()))
    validation = @("corepack pnpm smoke:campaign-task-compiler", "corepack pnpm smoke:run-until-hold-bounded")
    hygiene_metadata = [pscustomobject]@{
      goal = "mega-goal-322"
      campaign_id = $CampaignId
      campaign_task_compiler_pilot = $true
      bounded_loop_pilot = $true
      old_residue = $false
      excluded_from_requeue = $false
      no_secrets = $true
      no_deploy = $true
      no_server_root = $true
      no_external_infrastructure = $true
      allowed_worker_id = $WorkerId
    }
    selected_worker_id = $WorkerId
    token_printed = $false
  }
}

function Test-ExistingSafeGeneratedTask {
  param($Task, [int]$Index)
  $allowed = @((Get-Prop -Object $Task -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") })
  $metadata = Get-Prop -Object $Task -Name "hygiene_metadata"
  $planner = Get-Prop -Object $Task -Name "planner_metadata"
  $campaign = [string](Get-Prop -Object $Task -Name "campaign_id" -Default (Get-Prop -Object $metadata -Name "campaign_id" -Default (Get-Prop -Object $planner -Name "source_campaign_id" -Default "")))
  return (
    [string](Get-Prop -Object $Task -Name "task_id") -eq (Get-TaskIdForIndex -Index $Index) -and
    $campaign -eq $CampaignId -and
    [string](Get-Prop -Object $Task -Name "risk" -Default "") -eq "low" -and
    [string](Get-Prop -Object $Task -Name "task_type" -Default "") -in @("docs", "test") -and
    [string](Get-Prop -Object $Task -Name "status" -Default "") -in @("queued", "completed") -and
    $allowed.Count -eq 1 -and $allowed[0] -eq (Get-AllowedPathForIndex -Index $Index)
  )
}

$campaign = Get-CampaignPlan
$planCampaignId = [string](Get-Prop -Object $campaign -Name "campaign_id" -Default $CampaignId)
$items = @((Get-Prop -Object $campaign -Name "tasks" -Default @()) | Where-Object { $null -ne $_ })
$existing = @(Get-ExistingTasks)
$blockers = [System.Collections.Generic.List[string]]::new()
$rejected = @()
$generated = @()

if ($planCampaignId -ne $CampaignId) { $blockers.Add("campaign_id_mismatch") | Out-Null }
if ($items.Count -lt 1) { $blockers.Add("campaign_tasks_missing") | Out-Null }
if ($items.Count -gt 3) { $blockers.Add("more_than_3_generated_tasks") | Out-Null }

$index = 0
foreach ($item in $items) {
  $index += 1
  $taskId = Get-TaskIdForIndex -Index $index
  $allowedExpected = Get-AllowedPathForIndex -Index $index
  $reasons = [System.Collections.Generic.List[string]]::new()
  $taskType = ([string](Get-Prop -Object $item -Name "task_type" -Default "docs")).ToLowerInvariant()
  $risk = ([string](Get-Prop -Object $item -Name "risk" -Default "low")).ToLowerInvariant()
  $allowed = @((Get-Prop -Object $item -Name "allowed_paths" -Default @()) | ForEach-Object { ([string]$_).Replace("\", "/") } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  $text = (@(
    Get-Prop -Object $item -Name "title" -Default ""
    Get-Prop -Object $item -Name "body" -Default ""
    Get-Prop -Object $item -Name "prompt_summary" -Default ""
  ) -join " ")
  if ($taskType -notin @("docs", "test")) { $reasons.Add("task_type_not_docs_or_test") | Out-Null }
  if ($risk -ne "low") { $reasons.Add("risk_not_low") | Out-Null }
  if ($allowed.Count -lt 1) { $reasons.Add("missing_allowed_paths") | Out-Null }
  if ($allowed.Count -gt 2) { $reasons.Add("too_many_allowed_paths") | Out-Null }
  if ($allowed.Count -gt 0 -and ($allowed.Count -ne 1 -or $allowed[0] -ne $allowedExpected)) { $reasons.Add("allowed_paths_not_exact_generated_path") | Out-Null }
  foreach ($path in $allowed) {
    if (Test-UnsafePath -Path $path) { $reasons.Add("unsafe_allowed_path") | Out-Null }
  }
  if (Test-UnsafeText -Text $text) { $reasons.Add("unsafe_requested_surface") | Out-Null }
  $capabilities = @((Get-Prop -Object $item -Name "required_capabilities" -Default @("codex", "docs", "windows")) | ForEach-Object { ([string]$_).ToLowerInvariant() })
  if ($capabilities.Count -gt 0 -and (@($capabilities | Where-Object { $_ -notin @("codex", "docs", "documentation", "windows", "powershell") }).Count -gt 0)) { $reasons.Add("worker_capability_mismatch") | Out-Null }
  $existingMatch = @($existing | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $taskId } | Select-Object -First 1)
  if ($existingMatch.Count -gt 0 -and -not (Test-ExistingSafeGeneratedTask -Task $existingMatch[0] -Index $index)) { $reasons.Add("generated_task_id_collision_with_old_residue") | Out-Null }
  if ($reasons.Count -gt 0) {
    $rejected += [pscustomobject]@{ item_index = $index; task_id = $taskId; reasons = @($reasons.ToArray()); token_printed = $false }
  } else {
    $task = New-GeneratedTask -Item $item -Index $index
    $task.depends_on = @(@((Get-Prop -Object $item -Name "depends_on" -Default @())) | ForEach-Object {
      $dep = [string]$_
      if ($dep -match "^\d+$") { Get-TaskIdForIndex -Index ([int]$dep) } else { $dep }
    })
    $generated += $task
  }
}

if (Test-DependencyCycle -Items $generated) {
  $blockers.Add("dependency_cycle") | Out-Null
  $rejected += [pscustomobject]@{ item_index = 0; task_id = $null; reasons = @("dependency_cycle"); token_printed = $false }
}

$created = @()
$wouldCreateItems = @()
foreach ($task in @($generated)) {
  $taskId = [string]$task.task_id
  $match = @($existing | Where-Object { [string](Get-Prop -Object $_ -Name "task_id") -eq $taskId } | Select-Object -First 1)
  if ($match.Count -gt 0) {
    $created += [pscustomobject]@{
      task_id = $taskId
      status = if ([string](Get-Prop -Object $match[0] -Name "status" -Default "") -eq "completed") { "existing_completed_generated_task" } else { "existing_safe_generated_task" }
      task_status = [string](Get-Prop -Object $match[0] -Name "status" -Default "queued")
      allowed_paths = @($task.allowed_paths)
      token_printed = $false
    }
  } else {
    $wouldCreateItems += $task
  }
}

if ($Mode -eq "apply" -and $Confirm -ne $ConfirmText) {
  $blockers.Add("confirmation_required") | Out-Null
} elseif ($Mode -eq "apply" -and $blockers.Count -eq 0 -and $rejected.Count -eq 0) {
  if ($FixtureStateDir) {
    New-Item -ItemType Directory -Force -Path $FixtureStateDir | Out-Null
    [pscustomobject]@{ tasks = @($existing + $wouldCreateItems) } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $FixtureStateDir "compiled-campaign-tasks.json") -Encoding UTF8
  } elseif ($wouldCreateItems.Count -gt 0) {
    if ([string]::IsNullOrWhiteSpace($ApiBase)) { throw "ApiBase is required for live apply." }
    $config = [pscustomobject]@{ auth_mode = if ($TokenFile) { "bearer_token" } else { "none" }; token_file = $TokenFile }
    foreach ($task in @($wouldCreateItems)) {
      Invoke-SkyBridgeApi -Method POST -Path "/v1/tasks" -ApiBase $ApiBase -Body $task -Config $config -TimeoutSeconds $TimeoutSeconds | Out-Null
    }
  }
  foreach ($task in @($wouldCreateItems)) {
    $created += [pscustomobject]@{ task_id = $task.task_id; status = "created_safe_generated_task"; task_status = "queued"; allowed_paths = @($task.allowed_paths); token_printed = $false }
  }
}

$oldResidue = [pscustomobject]@{
  failed_tasks_excluded = @($existing | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "failed" }).Count
  blocked_tasks_excluded = @($existing | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "blocked" }).Count
  completed_tasks_excluded = @($existing | Where-Object { ([string](Get-Prop -Object $_ -Name "status" -Default "")).ToLowerInvariant() -eq "completed" }).Count
  old_residue_selected = $false
  no_old_task_claimed = $true
  no_old_task_requeued = $true
  token_printed = $false
}

$report = [pscustomobject]@{
  schema = "skybridge.campaign_task_compiler.v1"
  ok = ($blockers.Count -eq 0 -and $rejected.Count -eq 0)
  mode = $Mode
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  project_id = $ProjectId
  campaign_id = $CampaignId
  campaign_valid = ($blockers.Count -eq 0 -and $rejected.Count -eq 0)
  generated_task_count = @($generated).Count
  generated_tasks = @($generated)
  rejected_items = @($rejected)
  dependency_order = @($generated | ForEach-Object { [string]$_.task_id })
  risk_summary = [pscustomobject]@{ low = @($generated | Where-Object { $_.risk -eq "low" }).Count; rejected = @($rejected).Count; token_printed = $false }
  policy_summary = [pscustomobject]@{
    docs_test_only = $true
    deterministic_ids = $true
    max_generated_tasks = 3
    unsafe_surfaces_rejected = @("deploy", "secrets", "server-root", "OpenResty", "Authelia", "DNS", "Cloudflare", "GitHub settings", "branch protection", "external infrastructure")
    blocked_paths_are_guardrails_only = $true
    token_printed = $false
  }
  would_create_tasks = (@($wouldCreateItems).Count -gt 0)
  would_create_task_items = @($wouldCreateItems | ForEach-Object { [pscustomobject]@{ task_id = $_.task_id; allowed_paths = @($_.allowed_paths); token_printed = $false } })
  created_tasks = @($created)
  old_residue_exclusion = $oldResidue
  forbidden_actions = [pscustomobject]@{
    deployment_task_generated = $false
    secrets_task_generated = $false
    server_root_task_generated = $false
    external_infrastructure_task_generated = $false
    github_settings_task_generated = $false
    old_task_claimed = $false
    old_task_requeued = $false
    project_control_unpaused = $false
    daemon_implemented = $false
    recursive_run_until_hold = $false
    token_printed = $false
  }
  safety = [pscustomobject]@{
    preview_default = $true
    apply_requires_exact_confirmation = $true
    generated_docs_test_only = $true
    blocked_paths_do_not_poison_safe_candidates = $true
    max_task_count_enforced = $true
    prompt_or_log_content_omitted = $true
    token_printed = $false
  }
  blockers = @($blockers.ToArray())
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 40
} else {
  "Schema:       $($report.schema)"
  "Mode:         $($report.mode)"
  "OK:           $($report.ok)"
  "Campaign:     $($report.campaign_id)"
  "Generated:    $($report.generated_task_count)"
  "Rejected:     $(@($report.rejected_items).Count)"
  "TokenPrinted: false"
}
