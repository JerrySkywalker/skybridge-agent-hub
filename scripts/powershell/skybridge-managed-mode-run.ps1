[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("registry", "archive", "allocate-next", "next-run-preview", "next-run-gate", "safe-summary", "evidence", "run-preview", "run-apply")]
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
  [int]$MaxRuntimeMinutes = 10,
  [int]$ActiveTasks = 0,
  [int]$StaleLeases = 0,
  [string]$RunnerLock = "none",
  [switch]$SimulateOpenRun,
  [switch]$SimulatePriorOpenPr,
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
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript|raw_ci_log|token_printed"\s*:\s*true'
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
function Get-TaskPrBodyPath { Join-Path (Get-StateDirPath) "task-pr-body.md" }
function Get-Archive208Path { Join-Path (Get-RegistryDirPath) "managed-mode-pilot-208-archive.json" }

function Read-SafeJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-SecretLookingText $text) { throw "Secret-looking JSON file detected: $(ConvertTo-ShortPath $Path)" }
  $text | ConvertFrom-Json
}

function ConvertTo-NormalizedGitPath {
  param([string]$Path)
  $Path.Replace("\", "/").Trim()
}

function Get-ChangedFiles {
  $files = @()
  $porcelain = @(git status --porcelain=v1)
  if ($LASTEXITCODE -ne 0) { return @() }
  foreach ($line in $porcelain) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $path = $line.Substring(3).Trim()
    if ($path -match ' -> ') { $path = ($path -split ' -> ')[-1] }
    $files += $path
  }
  @($files | ForEach-Object { ConvertTo-NormalizedGitPath ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
}

function Test-PathAllowedForRun {
  param([string]$Path)
  $normalized = ConvertTo-NormalizedGitPath $Path
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function Get-CodexCommand {
  $commands = @(Get-Command "codex" -All -ErrorAction SilentlyContinue)
  if ($commands.Count -eq 0) { return $null }
  $preferred = @(
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".exe" } | Select-Object -First 1
    $commands | Where-Object { [System.IO.Path]::GetExtension([string]$_.Source).ToLowerInvariant() -eq ".cmd" } | Select-Object -First 1
    $commands | Select-Object -First 1
  ) | Where-Object { $null -ne $_ } | Select-Object -First 1
  $resolved = [string]$preferred.Source
  $extension = [System.IO.Path]::GetExtension($resolved).ToLowerInvariant()
  $repo = Get-RepoRoot
  if ($extension -eq ".cmd" -or $extension -eq ".bat") {
    $cmdHost = Get-Command "cmd.exe" -ErrorAction SilentlyContinue
    if (-not $cmdHost) { return $null }
    return [pscustomobject]@{
      file_path = [string]$cmdHost.Source
      argument_list = @("/d", "/s", "/c", "`"$resolved`" exec --sandbox workspace-write -")
      working_directory = $repo
      metadata = [pscustomobject]@{
        launcher_kind = $extension.TrimStart(".")
        command_profile_id = "profile_workspace_write_workdir"
        command_class = "codex_exec_workspace_write_workdir_stdin_discard_output"
        host_executable_name = "cmd.exe"
        prompt_persisted = $false
        transcript_persisted = $false
        stdout_persisted = $false
        stderr_persisted = $false
        token_printed = $false
      }
      token_printed = $false
    }
  }
  [pscustomobject]@{
    file_path = $resolved
    argument_list = @("exec", "--sandbox", "workspace-write", "-")
    working_directory = $repo
    metadata = [pscustomobject]@{
      launcher_kind = if ($extension) { $extension.TrimStart(".") } else { "extensionless" }
      command_profile_id = "profile_workspace_write_workdir"
      command_class = "codex_exec_workspace_write_workdir_stdin_discard_output"
      host_executable_name = [System.IO.Path]::GetFileName($resolved)
      prompt_persisted = $false
      transcript_persisted = $false
      stdout_persisted = $false
      stderr_persisted = $false
      token_printed = $false
    }
    token_printed = $false
  }
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
    state = if ($result.final_state) { [string]$result.final_state } else { "held_waiting_human_pr_review" }
    pr_url = if ($result.pr_url) { [string]$result.pr_url } else { $null }
    pr_state = if ($result.pr_created) { "open" } else { "none" }
    finalizer_evidence_path = $null
    evidence_hash = if (Test-Path -LiteralPath (Get-RunEvidencePath)) { Get-Sha256Text (Get-Content -Raw -LiteralPath (Get-RunEvidencePath)) } else { $null }
    created_at = if ($result.created_at) { [string]$result.created_at } else { $null }
    completed_at = if ($result.completed_at) { [string]$result.completed_at } else { $null }
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
    next_safe_action = "run one explicitly authorized low-risk docs/local-smoke workunit"
    token_printed = $false
  }
}

function New-RunPrompt {
@"
Create or update exactly this file:
$TargetPath

Write a short title and 3-6 concise bullet points explaining repeatable one-at-a-time managed mode.
Mention that each workunit creates one PR then stops for human review.
Mention that general bounded queue apply remains disabled.
Mention token_printed=false.

Hard limits:
- do not run tests, builds, git, gh, start-all, start-queue, generic bounded queue apply, resume -Apply or worker loops;
- do not touch code;
- do not touch any file outside $TargetPath;
- do not wait for user input;
- finish immediately after writing the file.
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
  $gate = New-NextRunGate
  $blockers = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($gate.blockers)) { $blockers.Add([string]$item) | Out-Null }
  if (-not $gate.can_run_one_at_a_time) { $blockers.Add("gate_blocked") | Out-Null }
  if (-not $Authorize209B) { $blockers.Add("explicit_209b_authorization_required") | Out-Null }
  if ([string]::IsNullOrWhiteSpace($AuthorizationReason)) { $blockers.Add("authorization_reason_required") | Out-Null }
  if ($TargetPath -ne "docs/managed-mode-repeatability-orientation.md") { $blockers.Add("unexpected_target_path") | Out-Null }
  if ($blockers.Count -gt 0) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      final_state = "blocked"
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
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_run_apply_result.v1"
      run_id = $ManagedModeRunId
      workunit_id = "$ManagedModeRunId-workunit-001"
      task_id = "$ManagedModeRunId-task-001"
      worker_id = $WorkerId
      task_type = $TaskType
      risk = $Risk
      final_state = "failed"
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
    return $result
  }

  $changedFiles = @(Get-ChangedFiles)
  if ($changedFiles.Count -lt 1) {
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
      changed_files = @()
      blockers = @("no_changed_files")
      token_printed = $false
    }
    Write-SafeJson $result (Get-RunResultPath)
    return $result
  }
  foreach ($file in $changedFiles) {
    if (-not (Test-PathAllowedForRun $file)) {
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
        blockers = @("disallowed_changed_path:$file")
        token_printed = $false
      }
      Write-SafeJson $result (Get-RunResultPath)
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
  "run-apply" { Invoke-RunApply }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
