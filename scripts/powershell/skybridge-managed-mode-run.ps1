[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("registry", "archive", "allocate-next", "next-run-preview", "next-run-gate", "safe-summary", "evidence", "run-preview", "run-apply", "run-invocation-diagnostics", "run-invocation-profile", "run-failure-state", "run-replacement-readiness", "run-replacement-preview", "run-finalizer-preview", "run-finalizer-apply", "run-finalizer-evidence", "run-finalizer-report", "changed-files-preview")]
  [string]$Command,

  [string]$ManagedModeRunId = "managed-mode-run-209",
  [string]$SourcePilotId = "managed-mode-pilot-208",
  [int]$SequenceNumber = 2,
  [string]$WorkerId = "laptop-zenbookduo",
  [string]$TaskType = "docs/local-smoke",
  [ValidateSet("low", "medium", "high")]
  [string]$Risk = "low",
  [string]$TargetPath = "docs/managed-mode-repeatability-orientation.md",
  [string]$StateDir = ".agent/tmp/managed-mode-run-209",
  [string]$RegistryDir = ".agent/tmp/managed-mode-run-registry",
  [switch]$Authorize209B,
  [string]$AuthorizationReason = "",
  [switch]$SimulateApply,
  [ValidateSet("success", "codex-failed", "bad-path", "no-changes")]
  [string]$SimulateApplyOutcome = "success",
  [switch]$AuthorizeReplacementRun,
  [string]$ReplacementAuthorizationReason = "",
  [int]$MaxRuntimeMinutes = 10,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [switch]$SimulateOpenRun,
  [switch]$SimulatePriorOpenPr,
  [switch]$SimulateFinalizerMergedPr,
  [switch]$SimulateFinalizerSecondRun,
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
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout(?!s?_persisted)|raw_stderr(?!s?_persisted)|raw_prompt(?!s?_persisted)|raw_worker_log(?!s?_persisted)|raw_codex_transcript(?!s?_persisted)|raw_ci_log(?!s?_persisted)|token_printed"\s*:\s*true'
}

function Get-Sha256Text {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "" } finally { $sha.Dispose() }
}

function Get-StateDirPath { Resolve-RepoPath $StateDir }
function Get-RegistryDirPath { Resolve-RepoPath $RegistryDir }
function Get-RunEvidencePath { Join-Path (Get-StateDirPath) "run-evidence.json" }
function Get-RunResultPath { Join-Path (Get-StateDirPath) "run-result.json" }
function Get-ReplacementResultPath { Join-Path (Get-StateDirPath) "replacement-result.json" }
function Get-FinalizerEvidencePath { Join-Path (Get-StateDirPath) "finalizer-evidence.json" }
function Get-FinalizerReportPath { Join-Path (Get-StateDirPath) "finalizer-report.json" }
function Get-TaskPrBodyPath { Join-Path (Get-StateDirPath) "task-pr-body.md" }
function Get-Archive208Path { Join-Path (Get-RegistryDirPath) "managed-mode-pilot-208-archive.json" }

function Get-CompletedRunState {
  "$($ManagedModeRunId.Replace("-", "_"))_completed"
}

function Get-AlreadyCompletedBlocker {
  "$($ManagedModeRunId.Replace("-", "_"))_already_completed"
}

function Read-SafeJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-SecretLookingText $text) { throw "Secret-looking JSON file detected: $(ConvertTo-ShortPath $Path)" }
  $text | ConvertFrom-Json
}

function ConvertTo-NormalizedGitPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $normalized = ([string]$Path).Replace("\", "/").Trim()
  if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
  return $normalized
}

function Get-ChangedFiles {
  $files = @()
  $unstaged = @(git diff --name-only)
  if ($LASTEXITCODE -eq 0) { $files += $unstaged }
  $staged = @(git diff --cached --name-only)
  if ($LASTEXITCODE -eq 0) { $files += $staged }
  $untracked = @(git ls-files --others --exclude-standard)
  if ($LASTEXITCODE -eq 0) { $files += $untracked }

  @($files |
    ForEach-Object { ConvertTo-NormalizedGitPath ([string]$_) } |
    Where-Object { $_ -and $_ -notlike ".agent/tmp/*" } |
    Select-Object -Unique)
}

function Test-PathAllowedForRun {
  param([string]$Path)
  $normalized = ConvertTo-NormalizedGitPath $Path
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function ConvertTo-WindowsCommandLineArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '"', '\"') + '"'
}

function New-CodexLauncherMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$LauncherKind,
    [Parameter(Mandatory = $true)][string]$HostExecutableName,
    [string]$CommandProfileId = "profile_workspace_write_workdir",
    [string]$CommandClass = "codex_exec_workspace_write_workdir_stdin_discard_output"
  )
  [pscustomobject]@{
    launcher_kind = $LauncherKind
    command_profile_id = $CommandProfileId
    selected_profile_id = $CommandProfileId
    command_class = $CommandClass
    host_executable_name = $HostExecutableName
    supports_workspace_write_workdir = $true
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function New-CodexInvocationProfile {
  param([string]$ProfileId = "profile_workspace_write_workdir")
  $repo = Get-RepoRoot
  switch ($ProfileId) {
    "profile_workspace_write_workdir" {
      [pscustomobject]@{
        profile_id = "profile_workspace_write_workdir"
        command_class = "codex_exec_workspace_write_workdir_stdin_discard_output"
        arguments = @("exec", "--sandbox", "workspace-write", "-")
        working_directory = $repo
        mutating = $true
        selected_for_managed_mode = $true
        token_printed = $false
      }
    }
    "profile_readonly_smoke" {
      [pscustomobject]@{
        profile_id = "profile_readonly_smoke"
        command_class = "codex_readonly_help_version_discard_output"
        arguments = @("--version")
        working_directory = $repo
        mutating = $false
        selected_for_managed_mode = $false
        token_printed = $false
      }
    }
    default {
      [pscustomobject]@{
        profile_id = "profile_disabled_unknown"
        command_class = "codex_profile_disabled_unknown"
        arguments = @()
        working_directory = $repo
        mutating = $false
        selected_for_managed_mode = $false
        token_printed = $false
      }
    }
  }
}

function Get-CodexCommand {
  param(
    [string]$ProfileId = "profile_workspace_write_workdir",
    [string[]]$OverrideArguments = @()
  )
  $profile = New-CodexInvocationProfile -ProfileId $ProfileId
  if ($profile.profile_id -eq "profile_disabled_unknown") { return $null }
  $commands = @(Get-Command "codex" -All -ErrorAction SilentlyContinue)
  if ($commands.Count -eq 0) { return $null }
  $preferred = @(
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".exe" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".cmd" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".bat" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".ps1" } | Select-Object -First 1
    $commands | Select-Object -First 1
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1
  $resolved = [string]$preferred.Source
  $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
  $fileName = [System.IO.Path]::GetFileName($resolved)
  $codexArgs = if ($OverrideArguments.Count -gt 0) { @($OverrideArguments) } else { @($profile.arguments | ForEach-Object { [string]$_ }) }
  if ($extension -eq ".exe") {
    return [pscustomobject]@{
      file_path = $resolved
      argument_list = @($codexArgs)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind "codex.exe" -HostExecutableName $fileName -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
      token_printed = $false
    }
  }
  if ($extension -eq ".cmd" -or $extension -eq ".bat") {
    $cmdHost = Get-Command "cmd.exe" -ErrorAction SilentlyContinue
    if (-not $cmdHost) { return $null }
    $commandLine = @(
      (ConvertTo-WindowsCommandLineArgument -Value $resolved)
      @($codexArgs | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) })
    ) -join " "
    return [pscustomobject]@{
      file_path = [string]$cmdHost.Source
      argument_list = @("/d", "/s", "/c", $commandLine)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind $extension.TrimStart(".") -HostExecutableName "cmd.exe" -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
      token_printed = $false
    }
  }

  if ($extension -eq ".ps1") {
    $pwsh = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if (-not $pwsh) { $pwsh = Get-Command "powershell.exe" -ErrorAction SilentlyContinue }
    if (-not $pwsh) { return $null }
    return [pscustomobject]@{
      file_path = [string]$pwsh.Source
      argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolved) + @($codexArgs)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind "ps1" -HostExecutableName ([System.IO.Path]::GetFileName([string]$pwsh.Source)) -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
      token_printed = $false
    }
  }

  if ([string]::IsNullOrWhiteSpace($extension)) {
    return [pscustomobject]@{
      file_path = $resolved
      argument_list = @($codexArgs)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind "extensionless" -HostExecutableName $fileName -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
      token_printed = $false
    }
  }

  return $null
}

function Invoke-SilentProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardInputText,
    [int]$TimeoutMinutes = 10
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
  $startedAt = Get-Date
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.StandardInput.Write($StandardInputText)
  $process.StandardInput.Close()
  $timedOut = -not $process.WaitForExit($TimeoutMinutes * 60 * 1000)
  if ($timedOut) { try { $process.Kill($true) } catch {} } else { $process.WaitForExit() }
  $completedAt = Get-Date
  $stdoutText = ""
  $stderrText = ""
  try { $stdoutText = [string]$stdoutTask.GetAwaiter().GetResult() } catch {}
  try { $stderrText = [string]$stderrTask.GetAwaiter().GetResult() } catch {}
  $stdoutChars = $stdoutText.Length
  $stderrChars = $stderrText.Length
  $stdoutText = $null
  $stderrText = $null
  [pscustomobject]@{
    ok = (-not $timedOut -and $process.ExitCode -eq 0)
    exit_code = if ($timedOut) { $null } else { $process.ExitCode }
    timed_out = $timedOut
    elapsed_seconds = [math]::Round(($completedAt - $startedAt).TotalSeconds, 3)
    timeout_minutes = $TimeoutMinutes
    stdout_chars_discarded = $stdoutChars
    stderr_chars_discarded = $stderrChars
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function New-SequencePolicy {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_sequence_policy.v1"
    max_open_runs = 1
    max_workunits_per_run = 1
    max_tasks_per_run = 1
    max_claims_per_run = 1
    max_codex_executions_per_run = 1
    max_prs_per_run = 1
    require_human_review = $true
    stop_on_pr_created = $true
    stop_on_ci_failure = $true
    stop_on_warning = $true
    general_bounded_queue_apply_enabled = $false
    one_at_a_time_run_apply_enabled = $false
    token_printed = $false
  }
}

function New-Completed208Archive {
  $finalizerPath = Resolve-RepoPath ".agent/tmp/managed-mode-pilot-208/finalizer-evidence.json"
  $finalizer = Read-SafeJsonFile -Path $finalizerPath
  $evidenceHash = if (Test-Path -LiteralPath $finalizerPath -PathType Leaf) { Get-Sha256Text (Get-Content -Raw -LiteralPath $finalizerPath) } else { $null }
  [pscustomobject]@{
    schema = "skybridge.managed_mode_completed_workunit_archive.v1"
    run_id = "managed-mode-pilot-208"
    pilot_id = "managed-mode-pilot-208"
    managed_mode_run_id = "managed-mode-pilot-208"
    sequence_number = 1
    source_workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    task_type = "docs/local-smoke"
    risk = "low"
    allowed_paths = @("docs/managed-mode-pilot-orientation.md")
    state = "completed"
    pr_url = if ($finalizer -and $finalizer.task_pr) { [string]$finalizer.task_pr.url } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140" }
    pr_state = "merged"
    finalizer_evidence_path = ".agent/tmp/managed-mode-pilot-208/finalizer-evidence.json"
    evidence_hash = $evidenceHash
    created_at = "2026-06-10T00:00:00.000Z"
    completed_at = if ($finalizer -and ($finalizer.PSObject.Properties.Name -contains "completed_at")) { [string]$finalizer.completed_at } else { "2026-06-10T00:00:00.000Z" }
    token_printed = $false
  }
}

function Get-OpenManagedModePrs {
  if ($SimulatePriorOpenPr) {
    return @([pscustomobject]@{ number = 209; url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; title = "Task managed-mode-run-209-workunit-001"; state = "OPEN"; token_printed = $false })
  }
  try {
    $output = gh pr list --state open --search "managed-mode-run in:title,body" --json number,url,title,headRefName,state --limit 50 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "*managed-mode-run*" -or [string]$_.title -like "*Managed Mode Run*" -or [string]$_.headRefName -like "ai/managed-mode-run/*"
    })
  } catch { @() }
}

function Get-Persisted209Record {
  $result = Read-SafeJsonFile -Path (Get-RunResultPath)
  if (-not $result) { return $null }
  $finalizerEvidencePath = Get-FinalizerEvidencePath
  $finalizer = Read-SafeJsonFile -Path $finalizerEvidencePath
  $finalizerCompleted = ($finalizer -and ($finalizer.PSObject.Properties.Name -contains "final_state") -and [string]$finalizer.final_state -eq (Get-CompletedRunState))
  $completedAt = if ($finalizerCompleted -and ($finalizer.PSObject.Properties.Name -contains "completed_at")) { [string]$finalizer.completed_at } elseif ($result.completed_at) { [string]$result.completed_at } else { $null }
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_record.v1"
    run_id = $ManagedModeRunId
    managed_mode_run_id = $ManagedModeRunId
    sequence_number = $SequenceNumber
    source_workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    task_type = $TaskType
    risk = $Risk
    allowed_paths = @($TargetPath)
    state = if ($finalizerCompleted) { "completed" } elseif ($result.final_state) { [string]$result.final_state } else { "held_waiting_human_pr_review" }
    pr_url = if ($result.pr_url) { [string]$result.pr_url } else { $null }
    pr_state = if ($finalizerCompleted) { "merged" } elseif ($result.pr_created) { "open" } else { "none" }
    finalizer_evidence_path = if ($finalizerCompleted) { ConvertTo-ShortPath $finalizerEvidencePath } else { $null }
    evidence_hash = if ($finalizerCompleted) { Get-Sha256Text (Get-Content -Raw -LiteralPath $finalizerEvidencePath) } elseif (Test-Path -LiteralPath (Get-RunEvidencePath)) { Get-Sha256Text (Get-Content -Raw -LiteralPath (Get-RunEvidencePath)) } else { $null }
    created_at = if ($result.created_at) { [string]$result.created_at } else { $null }
    completed_at = $completedAt
    token_printed = $false
  }
}

function New-Registry {
  $records = @()
  $records += New-Completed208Archive
  if ($SimulateOpenRun) {
    $records += [pscustomobject]@{
      schema = "skybridge.managed_mode_run_record.v1"
      run_id = $ManagedModeRunId
      managed_mode_run_id = $ManagedModeRunId
      sequence_number = $SequenceNumber
      source_workunit_id = "$ManagedModeRunId-workunit-001"
      task_id = "$ManagedModeRunId-task-001"
      worker_id = $WorkerId
      task_type = $TaskType
      risk = $Risk
      allowed_paths = @($TargetPath)
      state = "ready"
      pr_url = $null
      pr_state = "none"
      finalizer_evidence_path = $null
      evidence_hash = $null
      created_at = (Get-Date).ToUniversalTime().ToString("o")
      completed_at = $null
      token_printed = $false
    }
  }
  $persisted = Get-Persisted209Record
  if ($persisted) { $records += $persisted }
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_registry.v1"
    project_id = "skybridge-agent-hub"
    registry_id = "skybridge-managed-mode-run-registry"
    sequence_policy = New-SequencePolicy
    records = @($records)
    completed_runs = @($records | Where-Object { $_.state -eq "completed" })
    open_runs = @($records | Where-Object { $_.state -in @("ready", "held_waiting_human_pr_review", "blocked") })
    general_bounded_queue_apply_enabled = $false
    max_workunits = 1
    token_printed = $false
  }
}

function New-NextRunPreview {
  [pscustomobject]@{
    schema = "skybridge.one_at_a_time_managed_mode_gate.v1"
    run_id = $ManagedModeRunId
    managed_mode_run_id = $ManagedModeRunId
    sequence_number = $SequenceNumber
    source_workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    task_type = $TaskType
    risk = $Risk
    allowed_paths = @("README.md", "docs/**")
    target_path = $TargetPath
    selected_workunit_count = 1
    selected_worker_count = 1
    selected_worker_id = $WorkerId
    would_create_task = $true
    would_create_claim = $true
    would_execute_codex = $true
    would_create_pr = $true
    no_mutation = $true
    token_printed = $false
  }
}

function New-NextRunGate {
  $registry = New-Registry
  $openRuns = @($registry.open_runs)
  $openPrs = @(Get-OpenManagedModePrs)
  $blockers = New-Object System.Collections.Generic.List[string]
  if (@($registry.completed_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -gt 0) { $blockers.Add("completed_run_id_reuse_blocked") | Out-Null }
  if ($openRuns.Count -gt 0) { $blockers.Add("duplicate_open_run_blocked") | Out-Null }
  if ($openPrs.Count -gt 0) { $blockers.Add("prior_managed_mode_task_pr_open") | Out-Null }
  if ($ActiveTasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($StaleLeases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($RunnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if ($Risk -ne "low") { $blockers.Add("risk_not_low") | Out-Null }
  if ($TaskType -ne "docs/local-smoke") { $blockers.Add("task_type_not_docs_local_smoke") | Out-Null }
  if (-not (Test-PathAllowedForRun $TargetPath)) { $blockers.Add("target_path_not_allowed") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.one_at_a_time_managed_mode_gate.v1"
    run_id = $ManagedModeRunId
    managed_mode_run_id = $ManagedModeRunId
    sequence_number = $SequenceNumber
    can_run_one_at_a_time = ($blockers.Count -eq 0)
    explicit_209b_authorization_present = [bool]$Authorize209B
    run_apply_enabled = $false
    apply_disabled_reason = if ($Authorize209B) { "apply_requires_run-apply_command_and_all_gates" } else { "one_at_a_time_run_apply_disabled_by_default" }
    previous_run_208_completed = (@($registry.completed_runs | Where-Object { $_.run_id -eq "managed-mode-pilot-208" -and $_.state -eq "completed" }).Count -eq 1)
    completed_run_ids = @($registry.completed_runs | ForEach-Object { $_.run_id })
    open_run_count = $openRuns.Count
    open_managed_mode_pr_count = $openPrs.Count
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    general_bounded_queue_apply_enabled = $false
    max_workunits = 1
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-SafeSummary {
  $registry = New-Registry
  $gate = New-NextRunGate
  [pscustomobject]@{
    schema = "skybridge.managed_mode_repeatability_summary.v1"
    managed_mode_pilot_208 = "completed"
    next_mode = "repeatable one-at-a-time preview"
    next_run_id = $ManagedModeRunId
    next_sequence_number = $SequenceNumber
    general_bounded_queue = "disabled"
    general_bounded_queue_apply_enabled = $false
    one_at_a_time_run_apply_enabled = $false
    can_run_one_at_a_time = $gate.can_run_one_at_a_time
    apply_disabled_reason = $gate.apply_disabled_reason
    completed_run_count = @($registry.completed_runs).Count
    open_run_count = @($registry.open_runs).Count
    open_managed_mode_pr_count = $gate.open_managed_mode_pr_count
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    managed_mode_run_state = if (@($registry.completed_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -eq 1) { Get-CompletedRunState } elseif (@($registry.open_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -eq 1) { "held_waiting_human_pr_review" } else { "not_started" }
    managed_mode_run_209_state = if ($ManagedModeRunId -eq "managed-mode-run-209" -and @($registry.completed_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -eq 1) { "managed_mode_run_209_completed" } elseif ($ManagedModeRunId -eq "managed-mode-run-209" -and @($registry.open_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -eq 1) { "held_waiting_human_pr_review" } else { "not_started" }
    no_next_execution_authorized = $true
    next_safe_action = if (@($registry.completed_runs | Where-Object { $_.run_id -eq $ManagedModeRunId }).Count -eq 1) { "one-at-a-time mode ready for future explicit goal; no_next_execution_authorized" } else { "run one explicitly authorized low-risk docs/local-smoke workunit" }
    token_printed = $false
  }
}

function Get-ObjectStringArray {
  param($Object, [Parameter(Mandatory = $true)][string]$Name)
  if (-not $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) { return @() }
  @($Object.$Name | ForEach-Object { ConvertTo-NormalizedGitPath ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
}

function Test-StateDirFilesSafe {
  $stateDirPath = Get-StateDirPath
  if (-not (Test-Path -LiteralPath $stateDirPath -PathType Container)) {
    return [pscustomobject]@{ safe = $true; unsafe_files = @(); checked_file_count = 0; token_printed = $false }
  }
  $allowedNames = @(
    "run-result.json",
    "run-evidence.json",
    "replacement-result.json",
    "finalizer-evidence.json",
    "finalizer-report.json",
    "task-pr-body.md"
  )
  $unsafe = New-Object System.Collections.Generic.List[string]
  $files = @(Get-ChildItem -LiteralPath $stateDirPath -File -Force)
  foreach ($file in $files) {
    $name = [string]$file.Name
    if ($allowedNames -notcontains $name) {
      $unsafe.Add((ConvertTo-ShortPath $file.FullName)) | Out-Null
      continue
    }
    $text = Get-Content -Raw -LiteralPath $file.FullName
    if (Test-SecretLookingText $text) {
      $unsafe.Add((ConvertTo-ShortPath $file.FullName)) | Out-Null
    }
  }
  [pscustomobject]@{
    safe = ($unsafe.Count -eq 0)
    unsafe_files = @($unsafe)
    checked_file_count = $files.Count
    token_printed = $false
  }
}

function New-ChangedFilesPreview {
  $changedFiles = @(Get-ChangedFiles)
  $disallowed = @($changedFiles | Where-Object { -not (Test-PathAllowedForRun $_) })
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_changed_files_preview.v1"
    run_id = $ManagedModeRunId
    changed_files = @($changedFiles)
    changed_file_count = $changedFiles.Count
    allowed_paths = @("README.md", "docs/**")
    allowed = ($disallowed.Count -eq 0)
    disallowed_files = @($disallowed)
    token_printed = $false
  }
}

function New-RunInvocationDiagnostics {
  $versionCommand = Get-CodexCommand -ProfileId "profile_readonly_smoke" -OverrideArguments @("--version")
  $selected = Get-CodexCommand -ProfileId "profile_workspace_write_workdir"
  $version = if ($versionCommand) {
    Invoke-SilentProcess -FilePath $versionCommand.file_path -ArgumentList ([string[]]$versionCommand.argument_list) -WorkingDirectory $versionCommand.working_directory -StandardInputText "" -TimeoutMinutes 1
  } else { $null }
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_invocation_diagnostics.v1"
    run_id = $ManagedModeRunId
    launcher_kind = if ($selected) { [string]$selected.metadata.launcher_kind } else { $null }
    host_executable_name = if ($selected) { [string]$selected.metadata.host_executable_name } else { $null }
    selected_profile_id = if ($selected) { [string]$selected.metadata.command_profile_id } else { "profile_disabled_unknown" }
    command_class = if ($selected) { [string]$selected.metadata.command_class } else { "codex_profile_disabled_unknown" }
    supports_workspace_write_workdir = if ($selected) { "true" } else { "unknown" }
    version_exit_code = if ($version) { $version.exit_code } else { $null }
    version_output_chars_discarded = if ($version) { [int]$version.stdout_chars_discarded + [int]$version.stderr_chars_discarded } else { 0 }
    stdout_chars_discarded = if ($version) { [int]$version.stdout_chars_discarded } else { 0 }
    stderr_chars_discarded = if ($version) { [int]$version.stderr_chars_discarded } else { 0 }
    stdout_persisted = $false
    stderr_persisted = $false
    prompt_persisted = $false
    transcript_persisted = $false
    raw_logs_persisted = $false
    token_printed = $false
  }
}

function New-RunInvocationProfileSummary {
  $selected = Get-CodexCommand -ProfileId "profile_workspace_write_workdir"
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_invocation_profile.v1"
    run_id = $ManagedModeRunId
    selected_invocation_profile = if ($selected) { "profile_workspace_write_workdir" } else { "profile_disabled_unknown" }
    selected_profile_id = if ($selected) { "profile_workspace_write_workdir" } else { "profile_disabled_unknown" }
    selected_for_managed_mode = ($null -ne $selected)
    selected_reason = "Matches the completed managed-mode pilot executor profile: codex exec --sandbox workspace-write - with WorkingDirectory set to the repository root."
    profile_workspace_write_workdir = New-CodexInvocationProfile -ProfileId "profile_workspace_write_workdir"
    profile_readonly_smoke = New-CodexInvocationProfile -ProfileId "profile_readonly_smoke"
    profile_disabled_unknown = New-CodexInvocationProfile -ProfileId "profile_disabled_unknown"
    token_printed = $false
  }
}

function Get-RunFailureState {
  $resultPath = Get-RunResultPath
  $result = Read-SafeJsonFile -Path $resultPath
  $resultExists = Test-Path -LiteralPath $resultPath -PathType Leaf
  $fileScan = Test-StateDirFilesSafe
  $openPrs = @(Get-OpenManagedModePrs)
  $runEvidenceExists = Test-Path -LiteralPath (Get-RunEvidencePath) -PathType Leaf
  $finalizerEvidenceExists = Test-Path -LiteralPath (Get-FinalizerEvidencePath) -PathType Leaf
  $replacementExists = Test-Path -LiteralPath (Get-ReplacementResultPath) -PathType Leaf
  $resultChangedFiles = Get-ObjectStringArray -Object $result -Name "changed_files"
  $changedFiles = @($resultChangedFiles | Where-Object { $_ } | Select-Object -Unique)
  $prCreated = ($result -and ($result.PSObject.Properties.Name -contains "pr_created") -and $result.pr_created -eq $true)
  $prUrl = if ($result -and ($result.PSObject.Properties.Name -contains "pr_url")) { [string]$result.pr_url } else { "" }
  $timedOut = ($result -and ($result.PSObject.Properties.Name -contains "timed_out") -and $result.timed_out -eq $true)
  $ok = ($result -and ($result.PSObject.Properties.Name -contains "ok") -and $result.ok -eq $true)
  $started = ($result -and ($result.PSObject.Properties.Name -contains "codex_execution_started") -and $result.codex_execution_started -eq $true)
  $tokenPrinted = ($result -and ($result.PSObject.Properties.Name -contains "token_printed") -and $result.token_printed -eq $true)
  $rawFlags = ($result -and (
    (($result.PSObject.Properties.Name -contains "prompt_persisted") -and $result.prompt_persisted -eq $true) -or
    (($result.PSObject.Properties.Name -contains "transcript_persisted") -and $result.transcript_persisted -eq $true) -or
    (($result.PSObject.Properties.Name -contains "stdout_persisted") -and $result.stdout_persisted -eq $true) -or
    (($result.PSObject.Properties.Name -contains "stderr_persisted") -and $result.stderr_persisted -eq $true) -or
    (($result.PSObject.Properties.Name -contains "raw_logs_persisted") -and $result.raw_logs_persisted -eq $true)
  ))

  $classification = "invocation_failed_unknown"
  if (-not $resultExists) {
    $classification = "no_prior_attempt"
  } elseif ($replacementExists) {
    $classification = "replacement_exhausted"
  } elseif ($prCreated -or -not [string]::IsNullOrWhiteSpace($prUrl) -or $openPrs.Count -gt 0) {
    $classification = if ($ok) { "run_succeeded_created_pr" } else { "invocation_failed_with_pr" }
  } elseif (-not $fileScan.safe -or $rawFlags -or $tokenPrinted) {
    $classification = "invocation_failed_with_raw_artifacts"
  } elseif ($changedFiles.Count -gt 0) {
    $classification = "invocation_failed_with_changes"
  } elseif ($timedOut -and $started -and -not $runEvidenceExists -and -not $finalizerEvidenceExists) {
    $classification = "invocation_timed_out_no_mutation"
  } elseif ($started -and -not $ok -and -not $runEvidenceExists -and -not $finalizerEvidenceExists) {
    $classification = if ($result.exit_code -ne $null) { "invocation_failed_no_mutation" } else { "run_failed_no_mutation" }
  } elseif (-not $started -and -not $ok -and $changedFiles.Count -eq 0) {
    $classification = "run_failed_no_mutation"
  }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_failure_state.v1"
    run_id = $ManagedModeRunId
    workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    classification = $classification
    result_exists = $resultExists
    result_path = if ($resultExists) { ConvertTo-ShortPath $resultPath } else { $null }
    codex_execution_started = [bool]$started
    previous_exit_code = if ($result -and ($result.PSObject.Properties.Name -contains "exit_code")) { $result.exit_code } else { $null }
    previous_timed_out = [bool]$timedOut
    previous_changed_file_count = $changedFiles.Count
    changed_files = @($changedFiles)
    pr_created = [bool]$prCreated
    pr_url_present = -not [string]::IsNullOrWhiteSpace($prUrl)
    previous_open_pr_count = $openPrs.Count
    run_evidence_exists = $runEvidenceExists
    finalizer_evidence_exists = $finalizerEvidenceExists
    raw_or_secret_artifacts_present = (-not $fileScan.safe -or [bool]$rawFlags)
    unsafe_artifact_files = @($fileScan.unsafe_files)
    replacement_attempt_count = if ($replacementExists) { 1 } else { 0 }
    max_replacement_attempts = 1
    stdout_chars_discarded = if ($result -and ($result.PSObject.Properties.Name -contains "stdout_chars_discarded")) { [int]$result.stdout_chars_discarded } else { 0 }
    stderr_chars_discarded = if ($result -and ($result.PSObject.Properties.Name -contains "stderr_chars_discarded")) { [int]$result.stderr_chars_discarded } else { 0 }
    stdout_persisted = if ($result -and ($result.PSObject.Properties.Name -contains "stdout_persisted")) { [bool]$result.stdout_persisted } else { $false }
    stderr_persisted = if ($result -and ($result.PSObject.Properties.Name -contains "stderr_persisted")) { [bool]$result.stderr_persisted } else { $false }
    prompt_persisted = if ($result -and ($result.PSObject.Properties.Name -contains "prompt_persisted")) { [bool]$result.prompt_persisted } else { $false }
    transcript_persisted = if ($result -and ($result.PSObject.Properties.Name -contains "transcript_persisted")) { [bool]$result.transcript_persisted } else { $false }
    raw_logs_persisted = if ($result -and ($result.PSObject.Properties.Name -contains "raw_logs_persisted")) { [bool]$result.raw_logs_persisted } else { $false }
    token_printed = $false
  }
}

function New-RunReplacementReadiness {
  $failure = Get-RunFailureState
  $profile = New-RunInvocationProfileSummary
  $openPrs = @(Get-OpenManagedModePrs)
  $changed = @(Get-ChangedFiles)
  $blockers = New-Object System.Collections.Generic.List[string]
  if (@("invocation_failed_no_mutation", "run_failed_no_mutation") -notcontains $failure.classification) { $blockers.Add("previous_failure_not_no_mutation") | Out-Null }
  if ($failure.replacement_attempt_count -ne 0) { $blockers.Add("replacement_attempt_budget_exhausted") | Out-Null }
  if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { $blockers.Add("workspace_write_profile_not_selected") | Out-Null }
  if ($failure.previous_changed_file_count -ne 0 -or $changed.Count -ne 0) { $blockers.Add("prior_or_current_changed_files_present") | Out-Null }
  if ($failure.previous_open_pr_count -ne 0 -or $failure.pr_created -or $failure.pr_url_present -or $openPrs.Count -ne 0) { $blockers.Add("prior_or_open_pr_present") | Out-Null }
  if ($failure.run_evidence_exists) { $blockers.Add("run_evidence_present") | Out-Null }
  if ($failure.finalizer_evidence_exists) { $blockers.Add("finalizer_evidence_present") | Out-Null }
  if ($failure.raw_or_secret_artifacts_present) { $blockers.Add("raw_or_secret_artifacts_present") | Out-Null }
  if ($ActiveTasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($StaleLeases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($RunnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if ($WorkerId -ne "laptop-zenbookduo") { $blockers.Add("selected_worker_not_explicitly_eligible") | Out-Null }
  if ($TaskType -ne "docs/local-smoke") { $blockers.Add("task_type_not_docs_local_smoke") | Out-Null }
  if ($Risk -ne "low") { $blockers.Add("risk_not_low") | Out-Null }
  if ($TargetPath -ne "docs/managed-mode-repeatability-orientation.md" -or -not (Test-PathAllowedForRun $TargetPath)) { $blockers.Add("unexpected_target_path") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_replacement_readiness.v1"
    run_id = $ManagedModeRunId
    workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    selected_worker_count = 1
    task_type = $TaskType
    risk = $Risk
    target_path = $TargetPath
    can_run_replacement = ($blockers.Count -eq 0)
    previous_failure_classification = $failure.classification
    selected_invocation_profile = $profile.selected_invocation_profile
    selected_profile_id = $profile.selected_profile_id
    replacement_attempt_count = $failure.replacement_attempt_count
    max_replacement_attempts = 1
    open_managed_mode_pr_count = $openPrs.Count
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    general_bounded_queue_apply_enabled = $false
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-RunReplacementPreview {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_replacement_preview.v1"
    readiness = New-RunReplacementReadiness
    prompt_contract = [pscustomobject]@{
      target_path = "docs/managed-mode-repeatability-orientation.md"
      markdown_bullets = "3_to_6"
      broad_repo_inspection_allowed = $false
      tests_allowed = $false
      package_managers_allowed = $false
      git_or_gh_allowed = $false
      token_printed_required_false = $true
      token_printed = $false
    }
    would_execute_codex = $true
    would_create_one_task_pr_on_success = $true
    no_mutation = $true
    token_printed = $false
  }
}

function Get-TaskPrNumberFromUrl {
  param([string]$Url)
  if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
  if ($Url -match '/pull/(\d+)$') { return [int]$Matches[1] }
  return $null
}

function Get-RunTaskPrState {
  $result = Read-SafeJsonFile -Path (Get-RunResultPath)
  $evidence = Read-SafeJsonFile -Path (Get-RunEvidencePath)
  $prUrl = if ($result -and ($result.PSObject.Properties.Name -contains "pr_url")) { [string]$result.pr_url } elseif ($evidence -and ($evidence.PSObject.Properties.Name -contains "pr_url")) { [string]$evidence.pr_url } else { "" }
  if ($SimulateFinalizerMergedPr) {
    return [pscustomobject]@{ exists = $true; url = if ($prUrl) { $prUrl } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209" }; state = "MERGED"; merged = $true; token_printed = $false }
  }
  $number = Get-TaskPrNumberFromUrl -Url $prUrl
  if (-not $number) {
    $openPrs = @(Get-OpenManagedModePrs)
    if ($openPrs.Count -gt 0) {
      return [pscustomobject]@{ exists = $true; url = [string]$openPrs[0].url; state = [string]$openPrs[0].state; merged = $false; token_printed = $false }
    }
    return [pscustomobject]@{ exists = $false; url = $null; state = "missing"; merged = $false; token_printed = $false }
  }
  try {
    $json = gh pr view $number --json number,url,state,mergedAt,mergeCommit 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($json | Out-String).Trim())) {
      return [pscustomobject]@{ exists = $true; url = $prUrl; state = "unknown"; merged = $false; token_printed = $false }
    }
    $pr = $json | ConvertFrom-Json
    $merged = (-not [string]::IsNullOrWhiteSpace([string]$pr.mergedAt))
    return [pscustomobject]@{ exists = $true; url = [string]$pr.url; state = if ($merged) { "MERGED" } else { [string]$pr.state }; merged = $merged; merge_commit = if ($pr.mergeCommit) { [string]$pr.mergeCommit.oid } else { $null }; token_printed = $false }
  } catch {
    [pscustomobject]@{ exists = $true; url = $prUrl; state = "unknown"; merged = $false; token_printed = $false }
  }
}

function New-RunFinalizerState {
  $result = Read-SafeJsonFile -Path (Get-RunResultPath)
  $replacement = Read-SafeJsonFile -Path (Get-ReplacementResultPath)
  $evidence = Read-SafeJsonFile -Path (Get-RunEvidencePath)
  $fileScan = Test-StateDirFilesSafe
  $pr = Get-RunTaskPrState
  $finalizerExists = Test-Path -LiteralPath (Get-FinalizerEvidencePath) -PathType Leaf
  $changedFileExists = Test-Path -LiteralPath (Resolve-RepoPath $TargetPath) -PathType Leaf
  $codexCount = if ($result -and ($result.PSObject.Properties.Name -contains "codex_execution_count")) { [int]$result.codex_execution_count } elseif ($evidence -and ($evidence.PSObject.Properties.Name -contains "codex_execution_count")) { [int]$evidence.codex_execution_count } else { 0 }
  $prCount = if ($result -and ($result.PSObject.Properties.Name -contains "pr_count")) { [int]$result.pr_count } elseif ($evidence -and ($evidence.PSObject.Properties.Name -contains "pr_count")) { [int]$evidence.pr_count } else { 0 }
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($finalizerExists) { $blockers.Add((Get-AlreadyCompletedBlocker)) | Out-Null }
  if (-not $result -or -not $evidence) { $blockers.Add("run_success_evidence_missing") | Out-Null }
  if (-not $pr.exists) { $blockers.Add("task_pr_missing") | Out-Null }
  if ($pr.exists -and -not $pr.merged) { $blockers.Add("task_pr_not_merged") | Out-Null }
  if (-not $changedFileExists) { $blockers.Add("changed_file_missing_on_main") | Out-Null }
  if ($codexCount -ne 1) { $blockers.Add("codex_execution_count_not_one") | Out-Null }
  if ($prCount -ne 1) { $blockers.Add("pr_count_not_one") | Out-Null }
  if ($SimulateFinalizerSecondRun) { $blockers.Add("second_run_detected") | Out-Null }
  if (-not $fileScan.safe) { $blockers.Add("raw_or_secret_artifacts_present") | Out-Null }
  if ($ActiveTasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($StaleLeases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($RunnerLock -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_run_finalizer_state.v1"
    run_id = $ManagedModeRunId
    workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    can_finalize = ($blockers.Count -eq 0)
    final_state = if ($finalizerExists) { Get-CompletedRunState } elseif ($pr.exists -and -not $pr.merged) { "held_waiting_human_pr_review" } elseif ($blockers.Count -eq 0) { "ready_to_finalize" } else { "finalizer_blocked" }
    task_pr = $pr
    changed_file_exists_on_main = $changedFileExists
    exactly_one_workunit = $true
    exactly_one_task = $true
    exactly_one_claim = $true
    codex_execution_count = $codexCount
    pr_count = $prCount
    no_second_run = (-not $SimulateFinalizerSecondRun)
    no_raw_artifacts = $fileScan.safe
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    replacement_result_present = ($null -ne $replacement)
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Invoke-RunFinalizer {
  param([switch]$Mutate)
  $state = New-RunFinalizerState
  if (-not $Mutate) { return $state }
  if (-not $state.can_finalize) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_finalizer_result.v1"
      run_id = $ManagedModeRunId
      final_state = $state.final_state
      blockers = @($state.blockers)
      mutation = "refused"
      token_printed = $false
    }
  }
  $evidence = [pscustomobject]@{
    ok = $true
    schema = "skybridge.managed_mode_run_finalizer_evidence.v1"
    run_id = $ManagedModeRunId
    workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    final_state = Get-CompletedRunState
    task_pr = $state.task_pr
    changed_file = $TargetPath
    exactly_one_workunit = $true
    exactly_one_task = $true
    exactly_one_claim = $true
    codex_execution_count = 1
    pr_count = 1
    no_second_run = $true
    no_raw_artifacts = $true
    active_tasks = $ActiveTasks
    stale_leases = $StaleLeases
    runner_lock = $RunnerLock
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    token_printed = $false
  }
  Write-SafeJson $evidence (Get-FinalizerEvidencePath)
  $report = [pscustomobject]@{
    schema = "skybridge.managed_mode_run_finalizer_report.v1"
    run_id = $ManagedModeRunId
    final_state = Get-CompletedRunState
    evidence_path = ConvertTo-ShortPath (Get-FinalizerEvidencePath)
    token_printed = $false
  }
  Write-SafeJson $report (Get-FinalizerReportPath)
  $evidence
}

function New-RunPrompt {
@"
Create or update exactly this file:
$TargetPath

Write a short Markdown file with exactly 3-6 concise bullet points.
Explain repeatable one-at-a-time managed mode.
Mention that each workunit creates one PR then stops for human review.
Mention that general bounded queue apply remains disabled.
Mention token_printed=false.

Hard limits:
- do not inspect the broad repository;
- do not run tests;
- do not run package managers;
- do not run git or gh;
- do not run start-all, start-queue, generic bounded queue apply, resume -Apply or worker loops;
- do not touch files outside $TargetPath;
- do not wait for input;
- finish after writing the file.
"@
}

function Write-SafeJson {
  param($Object, [Parameter(Mandatory = $true)][string]$Path)
  $json = $Object | ConvertTo-Json -Depth 100
  if (Test-SecretLookingText $json) { throw "Secret-looking output blocked before persistence." }
  New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($Path)) -Force | Out-Null
  $json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Invoke-RunApply {
  $replacementMode = [bool]$AuthorizeReplacementRun
  $gate = New-NextRunGate
  $replacementReadiness = if ($replacementMode) { New-RunReplacementReadiness } else { $null }
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($replacementMode) {
    foreach ($item in @($replacementReadiness.blockers)) { $blockers.Add([string]$item) | Out-Null }
    if (-not $replacementReadiness.can_run_replacement) { $blockers.Add("replacement_readiness_blocked") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($ReplacementAuthorizationReason)) { $blockers.Add("replacement_authorization_reason_required") | Out-Null }
  } else {
    foreach ($item in @($gate.blockers)) { $blockers.Add([string]$item) | Out-Null }
    if (-not $gate.can_run_one_at_a_time) { $blockers.Add("gate_blocked") | Out-Null }
    if (-not $Authorize209B) { $blockers.Add("explicit_209b_authorization_required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($AuthorizationReason)) { $blockers.Add("authorization_reason_required") | Out-Null }
  }
  if ($TargetPath -ne "docs/managed-mode-repeatability-orientation.md") { $blockers.Add("unexpected_target_path") | Out-Null }
  if ($blockers.Count -gt 0) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      final_state = "blocked"
      mode = if ($replacementMode) { "replacement_blocked" } else { "run_apply_blocked" }
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      codex_execution_count = 0
      pr_created = $false
      pr_count = 0
      blockers = @($blockers | Select-Object -Unique)
      token_printed = $false
    }
  }

  if ($SimulateApply) {
    $changed = if ($SimulateApplyOutcome -eq "success") { @($TargetPath) } elseif ($SimulateApplyOutcome -eq "bad-path") { @("apps/server/src/index.ts") } else { @() }
    $result = [pscustomobject]@{
      ok = ($SimulateApplyOutcome -eq "success")
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      workunit_id = "$ManagedModeRunId-workunit-001"
      task_id = "$ManagedModeRunId-task-001"
      worker_id = $WorkerId
      task_type = $TaskType
      risk = $Risk
      final_state = if ($SimulateApplyOutcome -eq "success") { "held_waiting_human_pr_review" } else { "failed" }
      mode = if ($replacementMode) { "replacement_apply" } else { "run_apply" }
      selected_invocation_profile = "profile_workspace_write_workdir"
      replacement_attempt = if ($replacementMode) { 1 } else { 0 }
      replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
      max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = ($SimulateApplyOutcome -eq "success")
      pr_count = if ($SimulateApplyOutcome -eq "success") { 1 } else { 0 }
      changed_files = @($changed)
      no_mutation = $true
      auto_merge_enabled = $false
      stop_on_pr_created = $true
      token_printed = $false
    }
    return $result
  }

  $codex = Get-CodexCommand
  if (-not $codex) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      final_state = "blocked"
      mode = if ($replacementMode) { "replacement_blocked" } else { "run_apply_blocked" }
      blockers = @("codex_cli_missing")
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      codex_execution_count = 0
      pr_created = $false
      pr_count = 0
      token_printed = $false
    }
  }

  $branch = "ai/managed-mode-run/$ManagedModeRunId-workunit-001"
  New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch run branch failed." }

  $prompt = New-RunPrompt
  $promptHash = Get-Sha256Text $prompt
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory $codex.working_directory -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  $changedFilesAfterExecution = @(Get-ChangedFiles)
  if (-not $execution.ok) {
    if ($changedFilesAfterExecution.Count -eq 0) { git switch main *> $null }
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      workunit_id = "$ManagedModeRunId-workunit-001"
      task_id = "$ManagedModeRunId-task-001"
      worker_id = $WorkerId
      task_type = $TaskType
      risk = $Risk
      mode = if ($replacementMode) { if ($execution.timed_out) { "replacement_timeout" } else { "replacement_controlled_failure" } } else { "run_apply_controlled_failure" }
      final_state = if ($replacementMode) { if ($execution.timed_out) { "$($ManagedModeRunId.Replace("-", "_"))_timeout_replacement_exhausted" } else { "$($ManagedModeRunId.Replace("-", "_"))_failed_replacement_exhausted" } } else { "failed" }
      selected_invocation_profile = $codex.metadata.command_profile_id
      replacement_attempt = if ($replacementMode) { 1 } else { 0 }
      replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
      max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      pr_count = 0
      changed_files = @($changedFilesAfterExecution)
      timed_out = $execution.timed_out
      exit_code = $execution.exit_code
      stdout_chars_discarded = $execution.stdout_chars_discarded
      stderr_chars_discarded = $execution.stderr_chars_discarded
      stdout_persisted = $false
      stderr_persisted = $false
      prompt_persisted = $false
      transcript_persisted = $false
      raw_logs_persisted = $false
      auto_merge_enabled = $false
      token_printed = $false
    }
    Write-SafeJson $result (Get-RunResultPath)
    if ($replacementMode) { Write-SafeJson $result (Get-ReplacementResultPath) }
    return $result
  }

  $changedFiles = @(Get-ChangedFiles)
  if ($changedFiles.Count -lt 1) {
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      mode = if ($replacementMode) { "replacement_no_changes" } else { "run_apply_no_changes" }
      final_state = if ($replacementMode) { "$($ManagedModeRunId.Replace("-", "_"))_failed_replacement_exhausted" } else { "failed" }
      selected_invocation_profile = $codex.metadata.command_profile_id
      replacement_attempt = if ($replacementMode) { 1 } else { 0 }
      replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
      max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      pr_count = 0
      changed_files = @()
      blockers = @("no_changed_files")
      token_printed = $false
    }
    Write-SafeJson $result (Get-RunResultPath)
    if ($replacementMode) { Write-SafeJson $result (Get-ReplacementResultPath) }
    return $result
  }
  foreach ($file in $changedFiles) {
    if (-not (Test-PathAllowedForRun $file)) {
      $result = [pscustomobject]@{
        ok = $false
        schema = "skybridge.managed_mode_run_apply_result.v1"
        run_id = $ManagedModeRunId
        mode = if ($replacementMode) { "replacement_disallowed_path" } else { "run_apply_disallowed_path" }
        final_state = if ($replacementMode) { "$($ManagedModeRunId.Replace("-", "_"))_failed_replacement_exhausted" } else { "failed" }
        selected_invocation_profile = $codex.metadata.command_profile_id
        replacement_attempt = if ($replacementMode) { 1 } else { 0 }
        replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
        max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
        task_created = $true
        task_claimed = $true
        codex_execution_started = $true
        codex_execution_count = 1
        pr_created = $false
        pr_count = 0
        changed_files = @($changedFiles)
        blockers = @("disallowed_changed_path:$file")
        token_printed = $false
      }
      Write-SafeJson $result (Get-RunResultPath)
      if ($replacementMode) { Write-SafeJson $result (Get-ReplacementResultPath) }
      return $result
    }
  }
  if ($changedFiles.Count -ne 1 -or $changedFiles[0] -ne $TargetPath) {
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      final_state = "failed"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      pr_count = 0
      changed_files = @($changedFiles)
      blockers = @("expected_exact_target_path")
      token_printed = $false
    }
    Write-SafeJson $result (Get-RunResultPath)
    return $result
  }

  git add -- $TargetPath *> $null
  if ($LASTEXITCODE -ne 0) { throw "git add failed for $TargetPath" }
  git commit -m "docs: add managed mode run 209 orientation" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $body = @"
## Safe Summary

- Run id: `$ManagedModeRunId`
- Workunit id: `$ManagedModeRunId-workunit-001`
- Task id: `$ManagedModeRunId-task-001`
- Worker id: `$WorkerId`
- Task type: `$TaskType`
- Changed files: $($changedFiles -join ", ")
- No raw prompt, transcript, stdout, stderr, worker log, CI log or secret-bearing output is included.
- No auto-merge requested.
- token_printed=false
"@
  if (Test-SecretLookingText $body) { throw "Secret-looking PR body detected." }
  $body | Set-Content -LiteralPath (Get-TaskPrBodyPath) -Encoding UTF8
  $prOutput = gh pr create --title "Managed Mode Run 209: Task $ManagedModeRunId-workunit-001" --body-file (Get-TaskPrBodyPath) --base main --head $branch
  if ($LASTEXITCODE -ne 0) { throw "gh pr create failed." }
  $prUrl = (($prOutput | Out-String).Trim() -split "\r?\n" | Select-Object -Last 1)

  $fileText = Get-Content -Raw -LiteralPath (Resolve-RepoPath $TargetPath)
  $evidence = [pscustomobject]@{
    schema = "skybridge.managed_mode_run_record.v1"
    run_id = $ManagedModeRunId
    managed_mode_run_id = $ManagedModeRunId
    sequence_number = $SequenceNumber
    source_workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    task_type = $TaskType
    risk = $Risk
    allowed_paths = @($TargetPath)
    state = "held_waiting_human_pr_review"
    pr_url = $prUrl
    pr_state = "open"
    finalizer_evidence_path = $null
    evidence_hash = Get-Sha256Text $fileText
    prompt_sha256 = $promptHash
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    raw_logs_persisted = $false
    auto_merge_enabled = $false
    replacement_attempt = if ($replacementMode) { 1 } else { 0 }
    replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
    max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    completed_at = $null
    token_printed = $false
  }
  Write-SafeJson $evidence (Get-RunEvidencePath)
  $result = [pscustomobject]@{
    ok = $true
    schema = "skybridge.managed_mode_run_apply_result.v1"
    run_id = $ManagedModeRunId
    workunit_id = "$ManagedModeRunId-workunit-001"
    task_id = "$ManagedModeRunId-task-001"
    worker_id = $WorkerId
    task_type = $TaskType
    risk = $Risk
    final_state = "held_waiting_human_pr_review"
    mode = if ($replacementMode) { "replacement_apply" } else { "run_apply" }
    selected_invocation_profile = $codex.metadata.command_profile_id
    replacement_attempt = if ($replacementMode) { 1 } else { 0 }
    replacement_attempt_count = if ($replacementMode) { 1 } else { 0 }
    max_replacement_attempts = if ($replacementMode) { 1 } else { 0 }
    task_created = $true
    task_claimed = $true
    codex_execution_started = $true
    codex_execution_count = 1
    pr_created = $true
    pr_count = 1
    pr_url = $prUrl
    changed_files = @($changedFiles)
    evidence_path = ConvertTo-ShortPath (Get-RunEvidencePath)
    auto_merge_enabled = $false
    stop_on_pr_created = $true
    token_printed = $false
  }
  Write-SafeJson $result (Get-RunResultPath)
  if ($replacementMode) { Write-SafeJson $result (Get-ReplacementResultPath) }
  git switch main *> $null
  return $result
}

$result = switch ($Command) {
  "registry" { New-Registry }
  "archive" { New-Completed208Archive }
  "allocate-next" { New-NextRunPreview }
  "next-run-preview" { New-NextRunPreview }
  "next-run-gate" { New-NextRunGate }
  "safe-summary" { New-SafeSummary }
  "evidence" { $persisted = Get-Persisted209Record; if ($persisted) { $persisted } else { New-Registry } }
  "run-preview" { [pscustomobject]@{ schema = "skybridge.managed_mode_run_preview.v1"; preview = New-NextRunPreview; gate = New-NextRunGate; no_mutation = $true; token_printed = $false } }
  "run-invocation-diagnostics" { New-RunInvocationDiagnostics }
  "run-invocation-profile" { New-RunInvocationProfileSummary }
  "run-failure-state" { Get-RunFailureState }
  "run-replacement-readiness" { New-RunReplacementReadiness }
  "run-replacement-preview" { New-RunReplacementPreview }
  "run-finalizer-preview" { Invoke-RunFinalizer }
  "run-finalizer-apply" { Invoke-RunFinalizer -Mutate }
  "run-finalizer-evidence" { New-RunFinalizerState }
  "run-finalizer-report" { Invoke-RunFinalizer }
  "changed-files-preview" { New-ChangedFilesPreview }
  "run-apply" { Invoke-RunApply }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
