[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "readiness", "plan-preview", "apply-gate", "pilot-preview", "pilot-apply", "finalizer-preview", "finalizer-apply", "finalizer-evidence", "finalizer-report", "evidence", "safe-summary")]
  [string]$Command,

  [string]$PilotId = "managed-mode-pilot-208",
  [ValidateSet("low-docs", "production", "secrets", "github-settings", "auto-merge", "second-workunit", "second-worker", "bad-path")]
  [string]$Scenario = "low-docs",
  [int]$MaxWorkunits = 1,
  [int]$MaxTasks = 1,
  [int]$MaxClaims = 1,
  [int]$MaxCodexExecutions = 1,
  [int]$MaxPrs = 1,
  [int]$MaxRuntimeMinutes = 30,
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$StateDir = ".agent/tmp/managed-mode-pilot-208",
  [switch]$SimulateApply,
  [switch]$SimulateFinalizerMergedPr,
  [switch]$SimulateFinalizerSecondWorkunit,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Get-RepoRoot {
  (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
}

function Resolve-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) $Path))
}

function ConvertTo-ShortPath {
  param([string]$Path)
  $root = Get-RepoRoot
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $Path.Replace("\", "/")
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|token_printed"\s*:\s*true'
}

function Get-Sha256Text {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""
  } finally {
    $sha.Dispose()
  }
}

function ConvertTo-WindowsCommandLineArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '"', '\"') + '"'
}

function New-CodexLauncherMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$LauncherKind,
    [Parameter(Mandatory = $true)][string]$HostExecutableName
  )
  [pscustomobject]@{
    launcher_kind = $LauncherKind
    command_class = "codex_exec_ephemeral_stdin_discard_output"
    host_executable_name = $HostExecutableName
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function Invoke-SilentProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$StandardInputText,
    [int]$TimeoutMinutes = 30
  )
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  foreach ($arg in $ArgumentList) { [void]$psi.ArgumentList.Add($arg) }
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $psi
  [void]$process.Start()
  $process.StandardInput.Write($StandardInputText)
  $process.StandardInput.Close()
  $timedOut = -not $process.WaitForExit($TimeoutMinutes * 60 * 1000)
  if ($timedOut) {
    try { $process.Kill($true) } catch {}
  }
  [pscustomobject]@{
    ok = (-not $timedOut -and $process.ExitCode -eq 0)
    exit_code = if ($timedOut) { $null } else { $process.ExitCode }
    timed_out = $timedOut
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function Get-CodexCommand {
  $commands = @(Get-Command "codex" -All -ErrorAction SilentlyContinue)
  if ($commands.Count -eq 0) { return $null }
  $preferred = @(
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".exe" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".cmd" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".bat" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".ps1" } | Select-Object -First 1
    $commands | Select-Object -First 1
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1

  $resolvedPath = [string]$preferred.Source
  $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
  $fileName = [System.IO.Path]::GetFileName($resolvedPath)
  $codexArgs = @("exec", "--ephemeral", "--cd", (Get-RepoRoot), "-")

  if ($extension -eq ".exe") {
    return [pscustomobject]@{
      file_path = $resolvedPath
      argument_list = @($codexArgs)
      metadata = (New-CodexLauncherMetadata -LauncherKind "codex.exe" -HostExecutableName $fileName)
      token_printed = $false
    }
  }

  if ($extension -eq ".cmd" -or $extension -eq ".bat") {
    $cmdHost = Get-Command "cmd.exe" -ErrorAction SilentlyContinue
    if (-not $cmdHost) { return $null }
    $commandLine = @(
      (ConvertTo-WindowsCommandLineArgument -Value $resolvedPath)
      @($codexArgs | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) })
    ) -join " "
    return [pscustomobject]@{
      file_path = [string]$cmdHost.Source
      argument_list = @("/d", "/s", "/c", $commandLine)
      metadata = (New-CodexLauncherMetadata -LauncherKind $extension.TrimStart(".") -HostExecutableName "cmd.exe")
      token_printed = $false
    }
  }

  if ($extension -eq ".ps1") {
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command "powershell.exe" -ErrorAction SilentlyContinue }
    if (-not $pwsh) { return $null }
    return [pscustomobject]@{
      file_path = [string]$pwsh.Source
      argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($codexArgs)
      metadata = (New-CodexLauncherMetadata -LauncherKind "ps1" -HostExecutableName ([System.IO.Path]::GetFileName([string]$pwsh.Source)))
      token_printed = $false
    }
  }

  if ([string]::IsNullOrWhiteSpace($extension)) {
    return [pscustomobject]@{
      file_path = $resolvedPath
      argument_list = @($codexArgs)
      metadata = (New-CodexLauncherMetadata -LauncherKind "extensionless" -HostExecutableName $fileName)
      token_printed = $false
    }
  }

  return $null
}

function Get-StateDirPath {
  Resolve-RepoPath $StateDir
}

function Get-PilotEvidencePath {
  Join-Path (Get-StateDirPath) "pilot-evidence.json"
}

function Get-PilotResultPath {
  Join-Path (Get-StateDirPath) "pilot-result.json"
}

function Get-PilotFinalizerEvidencePath {
  Join-Path (Get-StateDirPath) "finalizer-evidence.json"
}

function Get-PilotFinalizerReportPath {
  Join-Path (Get-StateDirPath) "finalizer-report.json"
}

function Test-PathAllowedForPilot {
  param([string]$Path)
  $normalized = $Path.Replace("\", "/")
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function Get-ChangedFiles {
  $files = @()
  $raw = git diff --name-only
  if (-not [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { $files += @($raw) }
  $staged = git diff --cached --name-only
  if (-not [string]::IsNullOrWhiteSpace(($staged | Out-String).Trim())) { $files += @($staged) }
  @($files | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
}

function New-PilotPrompt {
@"
Execute exactly one SkyBridge managed-mode pilot workunit.

Task id: managed-mode-pilot-208-task-001
Workunit id: managed-mode-pilot-208-workunit-001
Pilot id: managed-mode-pilot-208
Worker: laptop-zenbookduo
Task type: docs/local-smoke

Make one small documentation-only update under docs/ that helps operators understand local managed-mode pilot smoke orientation. Prefer creating or updating docs/local-smoke-managed-mode-pilot-208.md.

Hard limits:
- modify only README.md or docs/**;
- do not touch secrets, .env files, production config, GitHub settings, branch protection, server-root config, OpenResty, Hermes config, or any repository outside this one;
- do not run git commit, git push, gh pr create, start-all, start-queue, resume -Apply, or any worker loop;
- do not persist raw prompts, transcripts, stdout, stderr or logs;
- keep the change small and reviewable.
"@
}

function Get-RunnerLockState {
  $lockPaths = @(
    ".agent/locks/skybridge-edge-worker.lock.json",
    ".agent/tmp/campaign-runner/bootstrap-trial-201.lock.json",
    ".agent/tmp/campaign-runner/dev-queue-189-200.lock.json",
    ".agent/tmp/campaign-runner/managed-mode-pilot-208.lock.json"
  )
  $present = @($lockPaths | Where-Object { Test-Path -LiteralPath (Resolve-RepoPath $_) -PathType Leaf })
  [pscustomobject]@{
    runner_lock_status = if ($present.Count -eq 0) { "none" } else { "present" }
    present_lock_count = $present.Count
    token_printed = $false
  }
}

function Get-GitState {
  $status = (git status --short | Out-String).Trim()
  [pscustomobject]@{
    branch = (git branch --show-current).Trim()
    clean = [string]::IsNullOrWhiteSpace($status)
    status_short = $status
    token_printed = $false
  }
}

function Get-OpenPilotPrs {
  try {
    $output = gh pr list --state open --search "$PilotId in:title,body" --json number,url,title,headRefName,state --limit 20 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    return @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "*Managed Mode Pilot 208*" -or
      [string]$_.title -like "*Task managed-mode-pilot-208-workunit-001*" -or
      [string]$_.headRefName -like "ai/managed-mode-pilot/*"
    })
  } catch {
    return @()
  }
}

function Get-PilotPrNumberFromUrl {
  param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  if ($Url -match '/pull/(\d+)(?:$|[/?#])') { return [int]$Matches[1] }
  return $null
}

function Read-PilotExecutorEvidence {
  $path = Get-PilotEvidencePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $path
  if (Test-SecretLookingText $text) { throw "Secret-looking pilot executor evidence detected." }
  $text | ConvertFrom-Json
}

function Test-SafeJsonObject {
  param($Object)
  $json = $Object | ConvertTo-Json -Depth 100 -Compress
  if (Test-SecretLookingText $json) { return $false }
  return ($json -match '"token_printed"\s*:\s*false' -and $json -notmatch '"token_printed"\s*:\s*true')
}

function Get-PilotTaskPrSnapshot {
  param($ExecutorEvidence)
  if ($SimulateFinalizerMergedPr) {
    return [pscustomobject]@{
      exists = $true
      number = 208
      url = if ($ExecutorEvidence -and $ExecutorEvidence.pr_url) { [string]$ExecutorEvidence.pr_url } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/208" }
      title = "Task managed-mode-pilot-208-workunit-001: Managed Mode Pilot 208 docs/local-smoke"
      state = "MERGED"
      merged = $true
      base_ref = "main"
      head_ref = "ai/managed-mode-pilot/managed-mode-pilot-208-workunit-001"
      changed_files = @($ExecutorEvidence.changed_files)
      token_printed = $false
    }
  }

  $number = if ($ExecutorEvidence) { Get-PilotPrNumberFromUrl -Url ([string]$ExecutorEvidence.pr_url) } else { $null }
  if (-not $number) {
    try {
      $search = gh pr list --state all --search "$PilotId in:title,body" --json number,url,title,headRefName,baseRefName,state,mergedAt --limit 20 2>$null
      if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($search | Out-String).Trim())) {
        $candidate = @($search | ConvertFrom-Json | Where-Object {
          [string]$_.title -like "*Managed Mode Pilot 208*" -or
          [string]$_.title -like "*Task managed-mode-pilot-208-workunit-001*" -or
          [string]$_.headRefName -like "ai/managed-mode-pilot/*"
        } | Select-Object -First 1)
        if ($candidate.Count -gt 0) { $number = [int]$candidate[0].number }
      }
    } catch {
      $number = $null
    }
  }
  if (-not $number) {
    return [pscustomobject]@{
      exists = $false
      number = $null
      url = if ($ExecutorEvidence) { [string]$ExecutorEvidence.pr_url } else { $null }
      title = $null
      state = "missing"
      merged = $false
      base_ref = $null
      head_ref = $null
      changed_files = @()
      token_printed = $false
    }
  }
  try {
    $raw = gh pr view $number --json number,url,title,state,merged,baseRefName,headRefName,files 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { throw "gh pr view failed" }
    $pr = $raw | ConvertFrom-Json
    [pscustomobject]@{
      exists = $true
      number = [int]$pr.number
      url = [string]$pr.url
      title = [string]$pr.title
      state = [string]$pr.state
      merged = [bool]$pr.merged
      base_ref = [string]$pr.baseRefName
      head_ref = [string]$pr.headRefName
      changed_files = @($pr.files | ForEach-Object { [string]$_.path })
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{
      exists = $false
      number = $number
      url = if ($ExecutorEvidence) { [string]$ExecutorEvidence.pr_url } else { $null }
      title = $null
      state = "unavailable"
      merged = $false
      base_ref = $null
      head_ref = $null
      changed_files = @()
      token_printed = $false
    }
  }
}

function New-PilotPolicy {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_policy.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    max_workunits = $MaxWorkunits
    max_tasks = $MaxTasks
    max_claims = $MaxClaims
    max_codex_executions = $MaxCodexExecutions
    max_prs = $MaxPrs
    max_runtime_minutes = $MaxRuntimeMinutes
    max_parallel_per_repo = 1
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    require_human_review = $true
    allow_task_types = @("docs", "local-smoke", "docs/local-smoke")
    block_task_types = @("production_deploy", "secret_rotation", "server_root_config", "dns", "openresty_config", "hermes_config", "github_settings", "branch_protection", "arbitrary_shell", "auto_execution", "auto_merge")
    allowed_paths = @("README.md", "docs/**")
    selected_worker_id = $WorkerId
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $true
    token_printed = $false
  }
}

function New-PilotWorkunit {
  param([int]$Index = 1)
  $taskType = "docs/local-smoke"
  $risk = "low"
  $allowedPaths = @("README.md", "docs/**")
  $title = "Managed Mode Pilot 208 local smoke documentation orientation"
  $blockers = @()
  if ($Scenario -eq "production") {
    $taskType = "production_deploy"
    $risk = "high"
    $title = "Production deploy"
    $blockers += "blocked_high_risk_surface"
  }
  if ($Scenario -eq "secrets") {
    $taskType = "secret_rotation"
    $risk = "high"
    $title = "Secret rotation"
    $blockers += "blocked_secret_surface"
  }
  if ($Scenario -eq "github-settings") {
    $taskType = "github_settings"
    $risk = "high"
    $allowedPaths = @(".github/**")
    $title = "GitHub branch protection update"
    $blockers += "blocked_github_settings_surface"
  }
  if ($Scenario -eq "auto-merge") {
    $blockers += "auto_merge_forbidden"
  }
  if ($Scenario -eq "bad-path") {
    $allowedPaths = @("apps/server/src/index.ts")
    $blockers += "path_allowlist_violation"
  }
  [pscustomobject]@{
    schema = "skybridge.workunit.v1"
    workunit_id = "managed-mode-pilot-208-workunit-{0:d3}" -f $Index
    project_id = "skybridge-agent-hub"
    campaign_id = $PilotId
    goal_id = "goal-208b-one-workunit-bounded-queue-pilot"
    title = $title
    task_id = "managed-mode-pilot-208-task-{0:d3}" -f $Index
    task_type = $taskType
    required_capabilities = @("codex", "repo_local_docs")
    allowed_paths = @($allowedPaths)
    risk = $risk
    state = "ready"
    lease_id = $null
    lease_owner = $null
    retry_count = 0
    max_retries = 0
    result_artifact = "$StateDir/pilot-result.json"
    evidence_artifact = "$StateDir/pilot-evidence.json"
    pr_url = $null
    ci_status = "not_started"
    requires_human_review = $true
    blockers = @($blockers)
    token_printed = $false
  }
}

function New-PilotPlan {
  $workunits = @(New-PilotWorkunit 1)
  if ($Scenario -eq "second-workunit") { $workunits += New-PilotWorkunit 2 }
  $routes = @(
    [pscustomobject]@{
      workunit_id = $workunits[0].workunit_id
      selected_worker_id = $WorkerId
      queue_order = 1
      token_printed = $false
    }
  )
  if ($Scenario -eq "second-worker") {
    $routes += [pscustomobject]@{
      workunit_id = $workunits[0].workunit_id
      selected_worker_id = "linux-ci-preview"
      queue_order = 1
      token_printed = $false
    }
  }
  [pscustomobject]@{
    schema = "skybridge.bounded_queue_apply_request.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    plan_id = "managed-mode-pilot-208-plan-preview"
    policy = New-PilotPolicy
    workunits = @($workunits)
    selected_routes = @($routes)
    selected_worker_count = @($routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count
    selected_workunit_count = @($workunits).Count
    would_create_tasks = $true
    would_claim_tasks = $true
    would_execute_tasks = $true
    would_create_prs = $true
    would_start_runner = $false
    no_mutation = $true
    token_printed = $false
  }
}

function New-ApplyGate {
  $policy = New-PilotPolicy
  $plan = New-PilotPlan
  $runner = Get-RunnerLockState
  $codex = Get-CodexCommand
  $openPrs = @(Get-OpenPilotPrs)
  $blockers = New-Object System.Collections.Generic.List[string]

  if ($PilotId -ne "managed-mode-pilot-208") { $blockers.Add("pilot_id_not_explicitly_authorized") | Out-Null }
  if ($policy.max_workunits -ne 1 -or @($plan.workunits).Count -ne 1) { $blockers.Add("max_workunits_must_equal_1") | Out-Null }
  if ($policy.max_tasks -ne 1) { $blockers.Add("max_tasks_must_equal_1") | Out-Null }
  if ($policy.max_claims -ne 1) { $blockers.Add("max_claims_must_equal_1") | Out-Null }
  if ($policy.max_codex_executions -ne 1) { $blockers.Add("max_codex_executions_must_equal_1") | Out-Null }
  if ($policy.max_prs -ne 1) { $blockers.Add("max_prs_must_equal_1") | Out-Null }
  if ($policy.max_runtime_minutes -gt 30) { $blockers.Add("max_runtime_minutes_too_high") | Out-Null }
  if (-not $policy.stop_on_pr_created) { $blockers.Add("stop_on_pr_created_required") | Out-Null }
  if (-not $policy.stop_on_ci_failure) { $blockers.Add("stop_on_ci_failure_required") | Out-Null }
  if (-not $policy.stop_on_warning) { $blockers.Add("stop_on_warning_required") | Out-Null }
  if (-not $policy.require_human_review) { $blockers.Add("human_review_required") | Out-Null }
  if ($policy.general_bounded_queue_apply_enabled) { $blockers.Add("general_bounded_queue_apply_must_remain_disabled") | Out-Null }
  if (-not $policy.pilot_bounded_queue_apply_enabled) { $blockers.Add("pilot_bounded_queue_apply_not_enabled") | Out-Null }
  if ($WorkerId -ne "laptop-zenbookduo") { $blockers.Add("selected_worker_must_be_laptop_zenbookduo") | Out-Null }
  if (-not $codex) { $blockers.Add("codex_cli_missing_or_unclassified") | Out-Null }
  if (@($plan.selected_routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count -ne 1) { $blockers.Add("exactly_one_worker_required") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if ($openPrs.Count -gt 0) { $blockers.Add("existing_open_pilot_pr") | Out-Null }

  foreach ($workunit in @($plan.workunits)) {
    if ($workunit.risk -ne "low") { $blockers.Add("risk_must_be_low") | Out-Null }
    if ($workunit.task_type -notin @("docs", "local-smoke", "docs/local-smoke")) { $blockers.Add("task_type_not_allowed:$($workunit.task_type)") | Out-Null }
    foreach ($path in @($workunit.allowed_paths)) {
      if ($path -ne "README.md" -and $path -ne "docs/**" -and $path -notlike "docs/*") { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
    }
    foreach ($item in @($workunit.blockers)) { $blockers.Add([string]$item) | Out-Null }
  }

  [pscustomobject]@{
    schema = "skybridge.bounded_queue_apply_gate.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    can_run_pilot = ($blockers.Count -eq 0)
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = ($blockers.Count -eq 0)
    active_tasks = 0
    stale_leases = 0
    runner_lock = $runner.runner_lock_status
    open_pilot_pr_count = $openPrs.Count
    selected_workunit_count = @($plan.workunits).Count
    selected_worker_count = @($plan.selected_routes | Select-Object -ExpandProperty selected_worker_id -Unique).Count
    launcher_metadata = if ($codex) { $codex.metadata } else { $null }
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-Readiness {
  $gate = New-ApplyGate
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_readiness.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    managed_mode_v1 = "pilot only"
    can_start_managed_mode = $false
    can_run_pilot = $gate.can_run_pilot
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $gate.pilot_bounded_queue_apply_enabled
    active_tasks = 0
    stale_leases = 0
    runner_lock = $gate.runner_lock
    blockers = @($gate.blockers)
    token_printed = $false
  }
}

function New-PilotState {
  $gate = New-ApplyGate
  $statePath = Resolve-RepoPath (Join-Path $StateDir "pilot-evidence.json")
  $finalizerPath = Get-PilotFinalizerEvidencePath
  $completed = Test-Path -LiteralPath $finalizerPath -PathType Leaf
  $existing = Test-Path -LiteralPath $statePath -PathType Leaf
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    state = if ($completed) { "managed_mode_pilot_completed" } elseif ($existing) { "held_waiting_human_pr_review" } elseif ($gate.can_run_pilot) { "ready_for_one_workunit_pilot" } else { "pilot_gate_blocked" }
    workunits_executed = if ($existing) { 1 } else { 0 }
    task_count = if ($existing) { 1 } else { 0 }
    claim_count = if ($existing) { 1 } else { 0 }
    codex_execution_count = if ($existing) { 1 } else { 0 }
    pr_count = if ($existing) { 1 } else { 0 }
    evidence_path = if ($existing) { ConvertTo-ShortPath $statePath } else { $null }
    finalizer_evidence_path = if ($completed) { ConvertTo-ShortPath $finalizerPath } else { $null }
    token_printed = $false
  }
}

function New-PilotFinalizerState {
  $executorEvidencePath = Get-PilotEvidencePath
  $finalizerEvidencePath = Get-PilotFinalizerEvidencePath
  $finalizerExists = Test-Path -LiteralPath $finalizerEvidencePath -PathType Leaf
  $executorEvidence = Read-PilotExecutorEvidence
  $prSnapshot = Get-PilotTaskPrSnapshot -ExecutorEvidence $executorEvidence
  $runner = Get-RunnerLockState
  $blockers = New-Object System.Collections.Generic.List[string]
  $changedFiles = @()
  $noRawArtifacts = $true
  $workunitCount = 0
  $taskCount = 0
  $claimCount = 0
  $codexExecutionCount = 0
  $prCount = 0

  if (-not $executorEvidence) {
    $blockers.Add("pilot_executor_evidence_missing") | Out-Null
  } else {
    $safe = Test-SafeJsonObject $executorEvidence
    if (-not $safe) {
      $blockers.Add("pilot_executor_evidence_unsafe") | Out-Null
      $noRawArtifacts = $false
    }
    $changedFiles = @($executorEvidence.changed_files | ForEach-Object { [string]$_ })
    $workunitCount = if ([string]$executorEvidence.workunit_id -eq "managed-mode-pilot-208-workunit-001") { 1 } else { 0 }
    $taskCount = if ([string]$executorEvidence.task_id -eq "managed-mode-pilot-208-task-001" -and $executorEvidence.task_created -eq $true) { 1 } else { 0 }
    $claimCount = if ($executorEvidence.task_claimed -eq $true) { 1 } else { 0 }
    $codexExecutionCount = [int]$executorEvidence.codex_execution_count
    $prCount = [int]$executorEvidence.pr_count
    if ($SimulateFinalizerSecondWorkunit) { $workunitCount = 2 }

    if ($workunitCount -ne 1) { $blockers.Add("expected_exactly_one_pilot_workunit") | Out-Null }
    if ($taskCount -ne 1) { $blockers.Add("expected_exactly_one_pilot_task") | Out-Null }
    if ($claimCount -ne 1) { $blockers.Add("expected_exactly_one_pilot_claim") | Out-Null }
    if ($codexExecutionCount -ne 1) { $blockers.Add("expected_exactly_one_codex_execution") | Out-Null }
    if ($prCount -ne 1) { $blockers.Add("expected_exactly_one_task_pr") | Out-Null }
    if ($executorEvidence.auto_merge_enabled -ne $false) { $blockers.Add("auto_merge_forbidden") | Out-Null }
    foreach ($file in $changedFiles) {
      if (-not (Test-PathAllowedForPilot -Path $file)) { $blockers.Add("path_allowlist_violation:$file") | Out-Null }
      if (-not (Test-Path -LiteralPath (Resolve-RepoPath $file) -PathType Leaf)) { $blockers.Add("changed_file_missing_on_main:$file") | Out-Null }
    }
  }

  if (-not $prSnapshot.exists) { $blockers.Add("pilot_task_pr_missing") | Out-Null }
  if ($prSnapshot.exists -and -not $prSnapshot.merged) { $blockers.Add("pilot_task_pr_not_merged") | Out-Null }
  if ($prSnapshot.base_ref -and $prSnapshot.base_ref -ne "main") { $blockers.Add("pilot_task_pr_base_not_main") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }

  $completed = ($finalizerExists -or ($blockers.Count -eq 0))
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_finalizer_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    state = if ($finalizerExists) { "managed_mode_pilot_completed" } elseif ($blockers.Count -eq 0) { "ready_to_finalize" } else { "held_waiting_human_pr_review" }
    final_state = if ($completed) { "managed_mode_pilot_completed" } else { "held_waiting_human_pr_review" }
    executor_evidence_path = if (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) { ConvertTo-ShortPath $executorEvidencePath } else { $null }
    finalizer_evidence_path = if ($finalizerExists) { ConvertTo-ShortPath $finalizerEvidencePath } else { $null }
    task_pr = $prSnapshot
    changed_files = @($changedFiles)
    workunits_executed = $workunitCount
    task_count = $taskCount
    claim_count = $claimCount
    codex_execution_count = $codexExecutionCount
    pr_count = $prCount
    no_second_workunit = ($workunitCount -eq 1)
    no_second_task_pr = ($prCount -eq 1)
    active_tasks = 0
    stale_leases = 0
    runner_lock = $runner.runner_lock_status
    no_raw_artifacts = $noRawArtifacts
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-PilotFinalizerEvidence {
  param([Parameter(Mandatory = $true)]$State)
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_finalizer_evidence.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    final_state = "managed_mode_pilot_completed"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    task_pr = $State.task_pr
    changed_files = @($State.changed_files)
    workunits_executed = $State.workunits_executed
    task_count = $State.task_count
    claim_count = $State.claim_count
    codex_execution_count = $State.codex_execution_count
    pr_count = $State.pr_count
    no_second_workunit = $State.no_second_workunit
    no_second_task_pr = $State.no_second_task_pr
    active_tasks = $State.active_tasks
    stale_leases = $State.stale_leases
    runner_lock = $State.runner_lock
    no_raw_artifacts = $State.no_raw_artifacts
    executor_evidence_path = $State.executor_evidence_path
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
}

function Invoke-PilotFinalizer {
  param([switch]$Mutate)
  $finalizerEvidencePath = Get-PilotFinalizerEvidencePath
  if ($Mutate -and (Test-Path -LiteralPath $finalizerEvidencePath -PathType Leaf)) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_finalizer_result.v1"
      pilot_id = $PilotId
      mode = "finalizer_apply"
      final_state = "managed_mode_pilot_completed"
      blockers = @("managed_mode_pilot_already_completed")
      token_printed = $false
    }
  }

  $state = New-PilotFinalizerState
  if (@($state.blockers).Count -gt 0) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_finalizer_result.v1"
      pilot_id = $PilotId
      mode = if ($Mutate) { "finalizer_apply_blocked" } else { "finalizer_preview" }
      final_state = "held_waiting_human_pr_review"
      state = $state
      blockers = @($state.blockers)
      no_mutation = (-not $Mutate)
      token_printed = $false
    }
  }

  $evidence = New-PilotFinalizerEvidence -State $state
  $report = [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_finalizer_report.v1"
    pilot_id = $PilotId
    final_state = "managed_mode_pilot_completed"
    dashboard = [pscustomobject]@{
      managed_mode_pilot_completed = $true
      no_next_execution_authorized = $true
      require_human_review = $true
      token_printed = $false
    }
    evidence_path = ConvertTo-ShortPath $finalizerEvidencePath
    token_printed = $false
  }
  if (-not (Test-SafeJsonObject $evidence) -or -not (Test-SafeJsonObject $report)) { throw "Secret-looking finalizer evidence detected." }

  if ($Mutate) {
    New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $finalizerEvidencePath -Encoding UTF8
    $report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Get-PilotFinalizerReportPath) -Encoding UTF8
  }

  [pscustomobject]@{
    ok = $true
    schema = "skybridge.managed_mode_pilot_finalizer_result.v1"
    pilot_id = $PilotId
    mode = if ($Mutate) { "finalizer_apply" } else { "finalizer_preview" }
    final_state = "managed_mode_pilot_completed"
    state = $state
    evidence = $evidence
    report = $report
    evidence_path = if ($Mutate) { ConvertTo-ShortPath $finalizerEvidencePath } else { $null }
    no_mutation = (-not $Mutate)
    token_printed = $false
  }
}

function Invoke-PilotApply {
  $gate = New-ApplyGate
  if (-not $gate.can_run_pilot) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "pilot_apply_blocked"
      final_state = "pilot_gate_blocked"
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @($gate.blockers)
      token_printed = $false
    }
  }
  if ($SimulateApply) {
    return [pscustomobject]@{
      ok = $true
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "simulated_pilot_apply_no_mutation"
      final_state = "held_waiting_human_pr_review"
      task_id = "managed-mode-pilot-208-task-001"
      workunit_id = "managed-mode-pilot-208-workunit-001"
      worker_id = "laptop-zenbookduo"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $true
      pr_count = 1
      auto_merge_enabled = $false
      no_mutation = $true
      token_printed = $false
    }
  }

  $git = Get-GitState
  if ($git.branch -ne "main" -or -not $git.clean) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "pilot_apply_blocked"
      final_state = "pilot_gate_blocked"
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("pilot_apply_requires_clean_main")
      token_printed = $false
    }
  }
  if (Test-Path -LiteralPath (Get-PilotEvidencePath) -PathType Leaf) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "pilot_apply_blocked"
      final_state = "held_waiting_human_pr_review"
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("existing_pilot_executor_evidence")
      token_printed = $false
    }
  }
  $codex = Get-CodexCommand
  if (-not $codex) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "pilot_apply_blocked"
      final_state = "pilot_gate_blocked"
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("codex_cli_missing")
      token_printed = $false
    }
  }

  $branch = "ai/managed-mode-pilot/managed-mode-pilot-208-workunit-001"
  $stateDirPath = Get-StateDirPath
  New-Item -ItemType Directory -Path $stateDirPath -Force | Out-Null
  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch pilot branch failed." }

  $prompt = New-PilotPrompt
  $promptHash = Get-Sha256Text -Text $prompt
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory (Get-RepoRoot) -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  if (-not $execution.ok) {
    git switch main *> $null
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = "controlled_failure"
      final_state = "held_no_execution_executor_failed"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      launcher_metadata = $codex.metadata
      pr_created = $false
      exit_code = $execution.exit_code
      timed_out = $execution.timed_out
      stdout_persisted = $false
      stderr_persisted = $false
      prompt_persisted = $false
      transcript_persisted = $false
      token_printed = $false
    }
  }

  $changedFiles = @(Get-ChangedFiles)
  if ($changedFiles.Count -lt 1) {
    git switch main *> $null
    throw "Managed mode pilot produced no changed files."
  }
  foreach ($file in $changedFiles) {
    if (-not (Test-PathAllowedForPilot -Path $file)) {
      git switch main *> $null
      throw "Managed mode pilot changed disallowed path: $file"
    }
  }
  foreach ($file in $changedFiles) {
    git add -- $file *> $null
    if ($LASTEXITCODE -ne 0) { throw "git add failed for $file" }
  }
  git commit -m "docs: add managed mode pilot smoke orientation" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $bodyPath = Join-Path $stateDirPath "task-pr-body.md"
  $body = @"
## Summary

Managed Mode Pilot 208 one-workunit docs/local-smoke task.

## Safety

- Pilot id: `managed-mode-pilot-208`
- Workunit id: `managed-mode-pilot-208-workunit-001`
- Task id: `managed-mode-pilot-208-task-001`
- Worker: `laptop-zenbookduo`
- Changed files: $($changedFiles -join ", ")
- No raw prompt, transcript, stdout, stderr, worker log or CI log is included.
- No auto-merge requested.
- token_printed=false
"@
  if (Test-SecretLookingText $body) { throw "Secret-looking PR body detected." }
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8
  $prOutput = gh pr create --title "Task managed-mode-pilot-208-workunit-001: Managed Mode Pilot 208 docs/local-smoke" --body-file $bodyPath --base main --head $branch
  if ($LASTEXITCODE -ne 0) { throw "gh pr create failed." }
  $prUrl = (($prOutput | Out-String).Trim() -split "\r?\n" | Select-Object -Last 1)

  $fileEvidence = @($changedFiles | ForEach-Object {
    [pscustomobject]@{
      path = $_
      sha256 = Get-Sha256Text -Text (Get-Content -Raw -LiteralPath (Resolve-RepoPath $_))
      token_printed = $false
    }
  })
  $evidence = [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_executor_evidence.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    command_class = "codex_exec_ephemeral_stdin_discard_output"
    launcher_metadata = $codex.metadata
    changed_files = @($changedFiles)
    file_evidence = @($fileEvidence)
    prompt_sha256 = $promptHash
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    output_persisted = $false
    task_created = $true
    task_claimed = $true
    codex_execution_count = 1
    pr_url = $prUrl
    pr_count = 1
    auto_merge_enabled = $false
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  }
  $evidenceJson = $evidence | ConvertTo-Json -Depth 60
  if (Test-SecretLookingText $evidenceJson) { throw "Secret-looking pilot evidence detected." }
  Set-Content -LiteralPath (Get-PilotEvidencePath) -Value $evidenceJson -Encoding UTF8
  $result = [pscustomobject]@{
    ok = $true
    schema = "skybridge.bounded_queue_apply_result.v1"
    pilot_id = $PilotId
    mode = "pilot_apply"
    final_state = "held_waiting_human_pr_review"
    task_id = "managed-mode-pilot-208-task-001"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    worker_id = "laptop-zenbookduo"
    launcher_metadata = $codex.metadata
    changed_files = @($changedFiles)
    pr_url = $prUrl
    task_created = $true
    task_claimed = $true
    codex_execution_started = $true
    codex_execution_count = 1
    pr_created = $true
    pr_count = 1
    evidence_path = ConvertTo-ShortPath (Get-PilotEvidencePath)
    auto_merge_enabled = $false
    token_printed = $false
  }
  $result | ConvertTo-Json -Depth 60 | Set-Content -LiteralPath (Get-PilotResultPath) -Encoding UTF8
  git switch main *> $null
  return $result
}

function New-SchemaSummary {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_schema_summary.v1"
    schemas = @(
      "skybridge.managed_mode_v1_readiness.v1",
      "skybridge.bounded_queue_apply_gate.v1",
      "skybridge.bounded_queue_apply_request.v1",
      "skybridge.bounded_queue_apply_result.v1",
      "skybridge.managed_mode_pilot_policy.v1",
      "skybridge.managed_mode_pilot_state.v1",
      "skybridge.managed_mode_pilot_finalizer_state.v1",
      "skybridge.managed_mode_pilot_finalizer_evidence.v1",
      "skybridge.managed_mode_pilot_finalizer_report.v1"
    )
    can_start_managed_mode = $false
    general_bounded_queue_apply_enabled = $false
    token_printed = $false
  }
}

function New-SafeSummary {
  $readiness = New-Readiness
  $gate = New-ApplyGate
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_safe_summary.v1"
    pilot_id = $PilotId
    managed_mode_v1 = "pilot only"
    general_apply = "disabled"
    one_workunit_pilot_possible_only_after_gate = $true
    can_start_managed_mode = $false
    can_run_pilot = $readiness.can_run_pilot
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $gate.pilot_bounded_queue_apply_enabled
    launcher_metadata = $gate.launcher_metadata
    max_workunits = $MaxWorkunits
    max_tasks = $MaxTasks
    max_claims = $MaxClaims
    max_codex_executions = $MaxCodexExecutions
    max_prs = $MaxPrs
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    token_printed = $false
  }
}

$result = switch ($Command) {
  "schema" { New-SchemaSummary }
  "readiness" { New-Readiness }
  "plan-preview" { New-PilotPlan }
  "apply-gate" { New-ApplyGate }
  "pilot-preview" { [pscustomobject]@{ schema = "skybridge.managed_mode_pilot_preview.v1"; request = New-PilotPlan; gate = New-ApplyGate; state = New-PilotState; no_mutation = $true; token_printed = $false } }
  "pilot-apply" { Invoke-PilotApply }
  "finalizer-preview" { Invoke-PilotFinalizer }
  "finalizer-apply" { Invoke-PilotFinalizer -Mutate }
  "finalizer-evidence" { New-PilotFinalizerState }
  "finalizer-report" { Invoke-PilotFinalizer }
  "evidence" { New-PilotState }
  "safe-summary" { New-SafeSummary }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
