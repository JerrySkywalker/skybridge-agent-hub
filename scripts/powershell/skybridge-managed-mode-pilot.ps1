[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("schema", "readiness", "plan-preview", "apply-gate", "pilot-preview", "pilot-apply", "timeout-state", "changed-files-preview", "retry-readiness", "retry-preview", "retry-apply", "codex-invocation-diagnostics", "codex-invocation-profile", "codex-invocation-compatibility", "codex-invocation-safe-summary", "replacement-retry-readiness", "replacement-retry-preview", "replacement-retry-apply", "finalizer-preview", "finalizer-apply", "finalizer-evidence", "finalizer-report", "evidence", "safe-summary")]
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
  [switch]$RenewedAuthorization,
  [string]$RenewedAuthorizationReason = "",
  [switch]$RequireRenewedAuthorization,
  [switch]$RetryAuthorization,
  [string]$RetryAuthorizationReason = "",
  [switch]$SimulateRetryApply,
  [ValidateSet("success", "timeout", "no-changes", "bad-path")]
  [string]$SimulateRetryOutcome = "success",
  [switch]$ReplacementRetryAuthorization,
  [string]$ReplacementRetryAuthorizationReason = "",
  [switch]$SimulateReplacementRetryApply,
  [ValidateSet("success", "timeout", "no-changes", "bad-path", "nonzero")]
  [string]$SimulateReplacementRetryOutcome = "success",
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
    [Parameter(Mandatory = $true)][string]$HostExecutableName,
    [string]$CommandProfileId = "profile_ephemeral_cd",
    [string]$CommandClass = "codex_exec_ephemeral_cd_stdin_discard_output"
  )
  [pscustomobject]@{
    launcher_kind = $LauncherKind
    command_profile_id = $CommandProfileId
    command_class = $CommandClass
    host_executable_name = $HostExecutableName
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
    "profile_ephemeral_cd" {
      [pscustomobject]@{
        profile_id = "profile_ephemeral_cd"
        command_class = "codex_exec_ephemeral_cd_stdin_discard_output"
        arguments = @("exec", "--ephemeral", "--cd", $repo, "-")
        working_directory = $repo
        mutating = $true
        selected_for_managed_mode = $false
        token_printed = $false
      }
    }
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

function Invoke-SilentProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardInputText,
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
  $startedAt = Get-Date
  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  $process.StandardInput.Write($StandardInputText)
  $process.StandardInput.Close()
  $timedOut = -not $process.WaitForExit($TimeoutMinutes * 60 * 1000)
  if ($timedOut) {
    try { $process.Kill($true) } catch {}
  } else {
    $process.WaitForExit()
  }
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

  $resolvedPath = [string]$preferred.Source
  $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
  $fileName = [System.IO.Path]::GetFileName($resolvedPath)
  $codexArgs = if ($OverrideArguments.Count -gt 0) { @($OverrideArguments) } else { @($profile.arguments | ForEach-Object { [string]$_ }) }

  if ($extension -eq ".exe") {
    return [pscustomobject]@{
      file_path = $resolvedPath
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
      (ConvertTo-WindowsCommandLineArgument -Value $resolvedPath)
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
      argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($codexArgs)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind "ps1" -HostExecutableName ([System.IO.Path]::GetFileName([string]$pwsh.Source)) -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
      token_printed = $false
    }
  }

  if ([string]::IsNullOrWhiteSpace($extension)) {
    return [pscustomobject]@{
      file_path = $resolvedPath
      argument_list = @($codexArgs)
      working_directory = $profile.working_directory
      profile = $profile
      metadata = (New-CodexLauncherMetadata -LauncherKind "extensionless" -HostExecutableName $fileName -CommandProfileId $profile.profile_id -CommandClass $profile.command_class)
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

function Get-PilotRetryResultPath {
  Join-Path (Get-StateDirPath) "retry-result.json"
}

function Get-PilotReplacementRetryResultPath {
  Join-Path (Get-StateDirPath) "replacement-retry-result.json"
}

function Test-DefaultPilotStateDir {
  $actual = [System.IO.Path]::GetFullPath((Get-StateDirPath)).TrimEnd("\", "/")
  $default = [System.IO.Path]::GetFullPath((Join-Path (Get-RepoRoot) ".agent/tmp/managed-mode-pilot-208")).TrimEnd("\", "/")
  $actual.Equals($default, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PilotFinalizerEvidencePath {
  Join-Path (Get-StateDirPath) "finalizer-evidence.json"
}

function Get-PilotFinalizerReportPath {
  Join-Path (Get-StateDirPath) "finalizer-report.json"
}

function Get-PilotTaskPrBodyPath {
  Join-Path (Get-StateDirPath) "task-pr-body.md"
}

function Get-PilotExpectedChangedFiles {
  @("docs/managed-mode-pilot-orientation.md")
}

function Test-SafeStateDirFiles {
  $stateDirPath = Get-StateDirPath
  if (-not (Test-Path -LiteralPath $stateDirPath -PathType Container)) {
    return [pscustomobject]@{
      safe = $true
      file_count = 0
      unsafe_files = @()
      unknown_files = @()
      token_printed = $false
    }
  }

  $allowedFileNames = @(
    "pilot-evidence.json",
    "pilot-result.json",
    "retry-result.json",
    "replacement-retry-result.json",
    "finalizer-evidence.json",
    "finalizer-report.json",
    "task-pr-body.md"
  )
  $unsafe = New-Object System.Collections.Generic.List[string]
  $unknown = New-Object System.Collections.Generic.List[string]
  $files = @(Get-ChildItem -LiteralPath $stateDirPath -File -Recurse -ErrorAction SilentlyContinue)
  foreach ($file in $files) {
    $short = ConvertTo-ShortPath $file.FullName
    if ($allowedFileNames -notcontains $file.Name) { $unknown.Add($short) | Out-Null }
    if ($file.Name -match '(?i)raw|transcript|stdout|stderr|worker-log|ci-log|prompt') { $unsafe.Add($short) | Out-Null; continue }
    $text = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction SilentlyContinue
    if (Test-SecretLookingText $text) { $unsafe.Add($short) | Out-Null }
  }

  [pscustomobject]@{
    safe = ($unsafe.Count -eq 0)
    file_count = $files.Count
    unsafe_files = @($unsafe)
    unknown_files = @($unknown)
    token_printed = $false
  }
}

function Read-SafeJsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  $text = Get-Content -Raw -LiteralPath $Path
  if (Test-SecretLookingText $text) { throw "Secret-looking state file detected: $(ConvertTo-ShortPath $Path)" }
  $text | ConvertFrom-Json
}

function Get-ObjectStringArray {
  param($Object, [string]$Name)
  if (-not $Object) { return @() }
  if (-not ($Object.PSObject.Properties.Name -contains $Name)) { return @() }
  @($Object.$Name | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
}

function New-TimeoutState {
  $openPrs = @(Get-OpenPilotPrs)
  $fileScan = Test-SafeStateDirFiles
  $resultPath = Get-PilotResultPath
  $retryPath = Get-PilotRetryResultPath
  $result = Read-SafeJsonFile -Path $resultPath
  $retryResult = Read-SafeJsonFile -Path $retryPath
  $executorEvidenceExists = Test-Path -LiteralPath (Get-PilotEvidencePath) -PathType Leaf
  $finalizerEvidenceExists = Test-Path -LiteralPath (Get-PilotFinalizerEvidencePath) -PathType Leaf
  $worktreeChangedFiles = if (Test-DefaultPilotStateDir) { @(Get-ChangedFiles) } else { @() }
  $resultChangedFiles = Get-ObjectStringArray -Object $result -Name "changed_files"
  $retryChangedFiles = Get-ObjectStringArray -Object $retryResult -Name "changed_files"
  $allChangedFiles = @($worktreeChangedFiles + $resultChangedFiles + $retryChangedFiles | Select-Object -Unique)
  $resultPrUrl = if ($result -and ($result.PSObject.Properties.Name -contains "pr_url")) { [string]$result.pr_url } else { "" }
  $retryPrUrl = if ($retryResult -and ($retryResult.PSObject.Properties.Name -contains "pr_url")) { [string]$retryResult.pr_url } else { "" }
  $resultPrCreated = ($result -and ($result.PSObject.Properties.Name -contains "pr_created") -and $result.pr_created -eq $true)
  $retryPrCreated = ($retryResult -and ($retryResult.PSObject.Properties.Name -contains "pr_created") -and $retryResult.pr_created -eq $true)
  $retryExists = Test-Path -LiteralPath $retryPath -PathType Leaf
  $resultExists = Test-Path -LiteralPath $resultPath -PathType Leaf
  $timedOut = ($result -and ($result.PSObject.Properties.Name -contains "timed_out") -and $result.timed_out -eq $true)
  $retryTimedOut = ($retryResult -and ($retryResult.PSObject.Properties.Name -contains "timed_out") -and $retryResult.timed_out -eq $true)
  $resultMode = if ($result -and ($result.PSObject.Properties.Name -contains "mode")) { [string]$result.mode } else { "" }
  $resultFinalState = if ($result -and ($result.PSObject.Properties.Name -contains "final_state")) { [string]$result.final_state } else { "" }
  $retryCount = if ($retryExists) { 1 } else { 0 }
  $blockers = New-Object System.Collections.Generic.List[string]

  if (-not $fileScan.safe) { $blockers.Add("prior_attempt_had_raw_or_secret_artifacts") | Out-Null }
  if ($executorEvidenceExists) { $blockers.Add("prior_attempt_executor_evidence_exists") | Out-Null }
  if ($finalizerEvidenceExists) { $blockers.Add("prior_attempt_finalizer_evidence_exists") | Out-Null }
  if ($openPrs.Count -gt 0 -or $resultPrCreated -or $retryPrCreated -or -not [string]::IsNullOrWhiteSpace($resultPrUrl) -or -not [string]::IsNullOrWhiteSpace($retryPrUrl)) { $blockers.Add("prior_attempt_created_pr") | Out-Null }
  if ($allChangedFiles.Count -gt 0) { $blockers.Add("prior_attempt_partial_worktree_dirty") | Out-Null }
  if ($retryExists) { $blockers.Add("retry_exhausted") | Out-Null }

  $priorState = "prior_attempt_ambiguous"
  if ($retryExists) {
    $priorState = "retry_exhausted"
  } elseif (-not $resultExists -and $openPrs.Count -eq 0 -and -not $executorEvidenceExists -and -not $finalizerEvidenceExists -and $fileScan.safe -and $allChangedFiles.Count -eq 0) {
    $priorState = "no_prior_attempt"
  } elseif (-not $fileScan.safe) {
    $priorState = "prior_attempt_unsafe_raw_artifacts"
  } elseif ($executorEvidenceExists) {
    $priorState = "prior_attempt_executor_evidence_exists"
  } elseif ($finalizerEvidenceExists) {
    $priorState = "prior_attempt_finalizer_evidence_exists"
  } elseif (@($blockers | Where-Object { $_ -eq "prior_attempt_created_pr" }).Count -gt 0) {
    $priorState = "prior_attempt_created_pr"
  } elseif ($allChangedFiles.Count -gt 0) {
    $priorState = "prior_attempt_partial_worktree_dirty"
  } elseif ($resultExists -and $timedOut -and ($result.token_printed -eq $false)) {
    $priorState = "prior_attempt_timed_out_no_mutation"
  } elseif ($resultExists -and -not $timedOut -and ($result.ok -eq $false) -and ($result.token_printed -eq $false)) {
    $priorState = "prior_attempt_failed_with_no_mutation"
  } elseif ($resultExists -and ($result.codex_execution_started -ne $true) -and ($result.token_printed -eq $false) -and ($resultMode -in @("controlled_failure", "renewed_controlled_failure") -or $resultFinalState -eq "held_no_execution_executor_failed")) {
    $priorState = "prior_attempt_failed_before_execution"
  }

  $timeoutDiagnostics = [pscustomobject]@{
    timeout = [bool]$timedOut
    retry_timeout = [bool]$retryTimedOut
    elapsed_seconds = if ($result -and ($result.PSObject.Properties.Name -contains "elapsed_seconds")) { $result.elapsed_seconds } else { $null }
    timeout_minutes = if ($result -and ($result.PSObject.Properties.Name -contains "timeout_minutes")) { $result.timeout_minutes } else { $MaxRuntimeMinutes }
    launcher_kind = if ($result -and $result.launcher_metadata) { [string]$result.launcher_metadata.launcher_kind } else { $null }
    host_executable_name = if ($result -and $result.launcher_metadata) { [string]$result.launcher_metadata.host_executable_name } else { $null }
    stdout_chars_discarded = if ($result -and ($result.PSObject.Properties.Name -contains "stdout_chars_discarded")) { $result.stdout_chars_discarded } else { $null }
    stderr_chars_discarded = if ($result -and ($result.PSObject.Properties.Name -contains "stderr_chars_discarded")) { $result.stderr_chars_discarded } else { $null }
    changed_file_count = $allChangedFiles.Count
    open_pr_count = $openPrs.Count
    executor_evidence_exists = $executorEvidenceExists
    finalizer_evidence_exists = $finalizerEvidenceExists
    retry_count = $retryCount
    token_printed = $false
  }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_timeout_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    prior_state = $priorState
    result_path = if ($resultExists) { ConvertTo-ShortPath $resultPath } else { $null }
    retry_result_path = if ($retryExists) { ConvertTo-ShortPath $retryPath } else { $null }
    timed_out = [bool]$timedOut
    changed_files = @($allChangedFiles)
    open_pilot_pr_count = $openPrs.Count
    executor_evidence_exists = $executorEvidenceExists
    finalizer_evidence_exists = $finalizerEvidenceExists
    raw_or_secret_artifacts_present = (-not $fileScan.safe)
    retry_count = $retryCount
    max_retries = 1
    retry_exhausted = ($retryCount -ge 1)
    diagnostics = $timeoutDiagnostics
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-RetryPolicy {
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_retry_policy.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    max_retries = 1
    retry_count = (New-TimeoutState).retry_count
    retry_reason_required = $true
    retry_allowed_only_after_timeout_no_mutation = $true
    retry_disallowed_after_pr = $true
    retry_disallowed_after_executor_evidence = $true
    retry_disallowed_after_partial_changes = $true
    retry_disallowed_after_unsafe_artifacts = $true
    token_printed = $false
  }
}

function New-RetryReadiness {
  $timeout = New-TimeoutState
  $gate = New-ApplyGate
  $policy = New-RetryPolicy
  $blockers = New-Object System.Collections.Generic.List[string]
  foreach ($item in @($gate.blockers)) { $blockers.Add([string]$item) | Out-Null }
  if (-not $gate.can_run_pilot) { $blockers.Add("pilot_gate_blocked") | Out-Null }
  if ($timeout.prior_state -ne "prior_attempt_timed_out_no_mutation") { $blockers.Add("prior_state_not_timeout_no_mutation") | Out-Null }
  if ($timeout.retry_count -ne 0) { $blockers.Add("retry_budget_exhausted") | Out-Null }
  if ($timeout.changed_files.Count -ne 0) { $blockers.Add("prior_attempt_changed_files_present") | Out-Null }
  if ($timeout.open_pilot_pr_count -ne 0) { $blockers.Add("prior_attempt_open_pr_present") | Out-Null }
  if ($timeout.executor_evidence_exists) { $blockers.Add("prior_executor_evidence_present") | Out-Null }
  if ($timeout.finalizer_evidence_exists) { $blockers.Add("prior_finalizer_evidence_present") | Out-Null }
  if ($timeout.raw_or_secret_artifacts_present) { $blockers.Add("prior_raw_or_secret_artifacts_present") | Out-Null }
  if ($gate.selected_workunit_count -ne 1) { $blockers.Add("exactly_one_workunit_required") | Out-Null }
  if ($gate.selected_worker_count -ne 1) { $blockers.Add("exactly_one_worker_required") | Out-Null }
  if (-not $RetryAuthorization -and $Command -eq "retry-apply") { $blockers.Add("retry_authorization_required") | Out-Null }
  if ($Command -eq "retry-apply" -and [string]::IsNullOrWhiteSpace($RetryAuthorizationReason)) { $blockers.Add("retry_authorization_reason_required") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_retry_readiness.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    can_retry = ($blockers.Count -eq 0)
    prior_state = $timeout.prior_state
    retry_count = $timeout.retry_count
    remaining_retry_count = [Math]::Max(0, 1 - [int]$timeout.retry_count)
    max_retries = 1
    policy = $policy
    gate = $gate
    timeout_state = $timeout
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function New-RenewedAuthorizationState {
  $openPrs = @(Get-OpenPilotPrs)
  $fileScan = Test-SafeStateDirFiles
  $executorEvidenceExists = Test-Path -LiteralPath (Get-PilotEvidencePath) -PathType Leaf
  $resultExists = Test-Path -LiteralPath (Get-PilotResultPath) -PathType Leaf
  $finalizerEvidenceExists = Test-Path -LiteralPath (Get-PilotFinalizerEvidencePath) -PathType Leaf
  $taskPrBodyExists = Test-Path -LiteralPath (Get-PilotTaskPrBodyPath) -PathType Leaf
  $blockers = New-Object System.Collections.Generic.List[string]

  if (-not $fileScan.safe) { $blockers.Add("prior_attempt_had_raw_or_secret_artifacts") | Out-Null }
  if ($executorEvidenceExists -or $openPrs.Count -gt 0 -or $finalizerEvidenceExists) { $blockers.Add("prior_attempt_already_produced_task_pr_or_evidence") | Out-Null }
  if ((-not $executorEvidenceExists) -and ($resultExists -or $taskPrBodyExists -or @($fileScan.unknown_files).Count -gt 0)) { $blockers.Add("prior_attempt_state_ambiguous") | Out-Null }

  $priorState = if (@($blockers | Where-Object { $_ -eq "prior_attempt_had_raw_or_secret_artifacts" }).Count -gt 0) {
    "prior_attempt_unsafe_raw_artifacts"
  } elseif (@($blockers | Where-Object { $_ -eq "prior_attempt_already_produced_task_pr_or_evidence" }).Count -gt 0) {
    "prior_attempt_produced_task_pr_or_evidence"
  } elseif (@($blockers | Where-Object { $_ -eq "prior_attempt_state_ambiguous" }).Count -gt 0) {
    "prior_attempt_ambiguous"
  } else {
    "prior_attempt_failed_before_execution"
  }

  if ($RequireRenewedAuthorization -or $RenewedAuthorization) {
    if (-not $RenewedAuthorization) { $blockers.Add("renewed_authorization_required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $blockers.Add("renewed_authorization_reason_required") | Out-Null }
    if ($priorState -ne "prior_attempt_failed_before_execution") { $blockers.Add("renewed_authorization_requires_prior_failed_before_execution") | Out-Null }
  }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_renewed_authorization_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    renewed_authorization = [bool]$RenewedAuthorization
    renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
    prior_attempt_state = $priorState
    prior_attempt_had_task_pr = ($openPrs.Count -gt 0)
    prior_attempt_open_task_pr_count = $openPrs.Count
    prior_attempt_had_executor_evidence = $executorEvidenceExists
    prior_attempt_had_result_artifact = $resultExists
    prior_attempt_had_finalizer_evidence = $finalizerEvidenceExists
    prior_attempt_had_raw_artifacts = (-not $fileScan.safe)
    prior_attempt_artifact_count = $fileScan.file_count
    prior_attempt_unknown_artifacts = @($fileScan.unknown_files)
    renewed_attempt_count = if ($RenewedAuthorization) { 1 } else { 0 }
    can_run_renewed_apply = ($blockers.Count -eq 0 -and $RenewedAuthorization -and -not [string]::IsNullOrWhiteSpace($RenewedAuthorizationReason))
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Test-PathAllowedForPilot {
  param([string]$Path)
  $normalized = $Path.Replace("\", "/")
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function ConvertTo-NormalizedGitPath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  $normalized = ([string]$Path).Trim().Replace("\", "/")
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
    ForEach-Object { ConvertTo-NormalizedGitPath -Path ([string]$_) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Select-Object -Unique)
}

function New-ChangedFilesPreview {
  $changedFiles = @(Get-ChangedFiles)
  $disallowed = @($changedFiles | Where-Object { -not (Test-PathAllowedForPilot -Path $_) })
  [pscustomobject]@{
    schema = "skybridge.managed_mode_changed_files_preview.v1"
    pilot_id = $PilotId
    changed_files = @($changedFiles)
    changed_file_count = $changedFiles.Count
    allowed_paths = @("README.md", "docs/**")
    allowed = ($disallowed.Count -eq 0)
    disallowed_files = @($disallowed)
    token_printed = $false
  }
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

function New-RetryPilotPrompt {
@"
Execute exactly one SkyBridge managed-mode pilot retry workunit.

Pilot id: managed-mode-pilot-208
Workunit id: managed-mode-pilot-208-workunit-001
Task id: managed-mode-pilot-208-task-001
Worker: laptop-zenbookduo
Retry attempt: 1 of 1
Task type: docs/local-smoke

Make one tiny documentation-only change by creating or updating exactly this file:
docs/managed-mode-pilot-orientation.md

Required content:
- a short title;
- 3 to 6 concise bullet points explaining that Managed Mode Pilot 208 is a one-workunit docs/local-smoke pilot;
- mention that the pilot task PR remains open for human review;
- mention token_printed=false as a safety invariant.

Hard limits:
- modify only docs/managed-mode-pilot-orientation.md;
- do not change code, package metadata, configuration, tests, scripts, README.md, .env files, secrets, production config, GitHub settings, branch protection, server-root config, OpenResty, Hermes config or any repository outside this one;
- do not run broad validation, tests, build, git commit, git push, gh pr create, start-all, start-queue, resume -Apply or any worker loop;
- do not wait for user input;
- do not use interactive actions;
- do not perform long exploration;
- do not persist raw prompts, transcripts, stdout, stderr or logs;
- finish immediately after writing the file.
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

function New-CodexInvocationDiagnostics {
  $versionCommand = Get-CodexCommand -ProfileId "profile_readonly_smoke" -OverrideArguments @("--version")
  $helpCommand = Get-CodexCommand -ProfileId "profile_readonly_smoke" -OverrideArguments @("exec", "--help")
  $selected = Get-CodexCommand -ProfileId "profile_workspace_write_workdir"
  $ephemeral = Get-CodexCommand -ProfileId "profile_ephemeral_cd"
  $unknown = Get-CodexCommand -ProfileId "profile_disabled_unknown"

  $version = if ($versionCommand) {
    Invoke-SilentProcess -FilePath $versionCommand.file_path -ArgumentList ([string[]]$versionCommand.argument_list) -WorkingDirectory $versionCommand.working_directory -StandardInputText "" -TimeoutMinutes 1
  } else { $null }
  $help = if ($helpCommand) {
    Invoke-SilentProcess -FilePath $helpCommand.file_path -ArgumentList ([string[]]$helpCommand.argument_list) -WorkingDirectory $helpCommand.working_directory -StandardInputText "" -TimeoutMinutes 1
  } else { $null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_codex_invocation_diagnostics.v1"
    pilot_id = $PilotId
    mode = "safe_readonly_codex_invocation_diagnostics"
    launcher_kind = if ($selected) { [string]$selected.metadata.launcher_kind } else { $null }
    host_executable_name = if ($selected) { [string]$selected.metadata.host_executable_name } else { $null }
    command_profile_id = if ($selected) { [string]$selected.metadata.command_profile_id } else { "profile_disabled_unknown" }
    selected_invocation_profile = if ($selected) { [string]$selected.metadata.command_profile_id } else { "profile_disabled_unknown" }
    supports_ephemeral = if ($ephemeral) { "unknown" } else { "false" }
    supports_cd_flag = if ($ephemeral) { "unknown" } else { "false" }
    supports_sandbox_workspace_write = if ($selected) { "true" } else { "unknown" }
    supports_stdin_prompt = if ($selected) { "true" } else { "unknown" }
    version_exit_code = if ($version) { $version.exit_code } else { $null }
    help_exit_code = if ($help) { $help.exit_code } else { $null }
    version_output_chars_discarded = if ($version) { [int]$version.stdout_chars_discarded + [int]$version.stderr_chars_discarded } else { 0 }
    help_output_chars_discarded = if ($help) { [int]$help.stdout_chars_discarded + [int]$help.stderr_chars_discarded } else { 0 }
    version_output_persisted = $false
    help_output_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    prompt_persisted = $false
    transcript_persisted = $false
    raw_logs_persisted = $false
    disabled_unknown_profile_available = ($null -ne $unknown)
    token_printed = $false
  }
}

function New-CodexInvocationProfileSummary {
  $selected = Get-CodexCommand -ProfileId "profile_workspace_write_workdir"
  [pscustomobject]@{
    schema = "skybridge.managed_mode_codex_invocation_profile.v1"
    pilot_id = $PilotId
    selected_invocation_profile = if ($selected) { "profile_workspace_write_workdir" } else { "profile_disabled_unknown" }
    selected_for_managed_mode = ($null -ne $selected)
    selected_reason = "Matches the previously successful bootstrap one-shot Codex executor profile: codex exec --sandbox workspace-write - with WorkingDirectory set to the repository root."
    profile_ephemeral_cd = New-CodexInvocationProfile -ProfileId "profile_ephemeral_cd"
    profile_workspace_write_workdir = New-CodexInvocationProfile -ProfileId "profile_workspace_write_workdir"
    profile_readonly_smoke = New-CodexInvocationProfile -ProfileId "profile_readonly_smoke"
    profile_disabled_unknown = New-CodexInvocationProfile -ProfileId "profile_disabled_unknown"
    token_printed = $false
  }
}

function Get-PreviousRetryClassification {
  $retryPath = Get-PilotRetryResultPath
  $replacementPath = Get-PilotReplacementRetryResultPath
  $retry = Read-SafeJsonFile -Path $retryPath
  $fileScan = Test-SafeStateDirFiles
  $openPrs = @(Get-OpenPilotPrs)
  $executorEvidenceExists = Test-Path -LiteralPath (Get-PilotEvidencePath) -PathType Leaf
  $finalizerEvidenceExists = Test-Path -LiteralPath (Get-PilotFinalizerEvidencePath) -PathType Leaf
  $worktreeChangedFiles = if (Test-DefaultPilotStateDir) { @(Get-ChangedFiles) } else { @() }
  $retryChangedFiles = Get-ObjectStringArray -Object $retry -Name "changed_files"
  $changedFiles = @($worktreeChangedFiles + $retryChangedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
  $retryExists = Test-Path -LiteralPath $retryPath -PathType Leaf
  $replacementExists = Test-Path -LiteralPath $replacementPath -PathType Leaf
  $retryOk = ($retry -and ($retry.PSObject.Properties.Name -contains "ok") -and $retry.ok -eq $true)
  $retryTimedOut = ($retry -and ($retry.PSObject.Properties.Name -contains "timed_out") -and $retry.timed_out -eq $true)
  $retryPrCreated = ($retry -and ($retry.PSObject.Properties.Name -contains "pr_created") -and $retry.pr_created -eq $true)
  $retryPrUrl = if ($retry -and ($retry.PSObject.Properties.Name -contains "pr_url")) { [string]$retry.pr_url } else { "" }
  $tokenPrinted = ($retry -and ($retry.PSObject.Properties.Name -contains "token_printed") -and $retry.token_printed -eq $true)
  $controlledFailure = ($retry -and (-not $retryOk) -and (($retry.PSObject.Properties.Name -contains "final_state") -or ($retry.PSObject.Properties.Name -contains "failure_class")))

  $classification = "invocation_failed_unknown"
  if (-not $retryExists) {
    $classification = "invocation_failed_unknown"
  } elseif ($retryPrCreated -or -not [string]::IsNullOrWhiteSpace($retryPrUrl) -or $openPrs.Count -gt 0) {
    $classification = "invocation_failed_with_pr"
  } elseif (-not $fileScan.safe) {
    $classification = "invocation_failed_with_raw_artifacts"
  } elseif ($changedFiles.Count -gt 0) {
    $classification = "invocation_failed_with_changes"
  } elseif ($retryTimedOut) {
    $classification = "invocation_timed_out_no_mutation"
  } elseif ($retryOk -and ($retryPrCreated -or -not [string]::IsNullOrWhiteSpace($retryPrUrl))) {
    $classification = "invocation_succeeded_created_pr"
  } elseif ($controlledFailure -and -not $executorEvidenceExists -and -not $finalizerEvidenceExists -and -not $tokenPrinted) {
    $classification = "invocation_failed_no_mutation"
  }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_codex_invocation_classification.v1"
    pilot_id = $PilotId
    previous_retry_result_exists = $retryExists
    previous_retry_result_path = if ($retryExists) { ConvertTo-ShortPath $retryPath } else { $null }
    classification = $classification
    failure_class = if ($retry -and ($retry.PSObject.Properties.Name -contains "failure_class")) { [string]$retry.failure_class } else { $null }
    timed_out = [bool]$retryTimedOut
    changed_files = @($changedFiles)
    pr_created = [bool]$retryPrCreated
    pr_url_present = -not [string]::IsNullOrWhiteSpace($retryPrUrl)
    open_pilot_pr_count = $openPrs.Count
    executor_evidence_exists = $executorEvidenceExists
    finalizer_evidence_exists = $finalizerEvidenceExists
    raw_or_secret_artifacts_present = (-not $fileScan.safe)
    replacement_retry_count = if ($replacementExists) { 1 } else { 0 }
    max_replacement_retries = 1
    prompt_persisted = if ($retry -and ($retry.PSObject.Properties.Name -contains "prompt_persisted")) { [bool]$retry.prompt_persisted } else { $false }
    transcript_persisted = if ($retry -and ($retry.PSObject.Properties.Name -contains "transcript_persisted")) { [bool]$retry.transcript_persisted } else { $false }
    stdout_persisted = if ($retry -and ($retry.PSObject.Properties.Name -contains "stdout_persisted")) { [bool]$retry.stdout_persisted } else { $false }
    stderr_persisted = if ($retry -and ($retry.PSObject.Properties.Name -contains "stderr_persisted")) { [bool]$retry.stderr_persisted } else { $false }
    raw_logs_persisted = if ($retry -and ($retry.PSObject.Properties.Name -contains "raw_logs_persisted")) { [bool]$retry.raw_logs_persisted } else { $false }
    token_printed = $false
  }
}

function New-CodexInvocationCompatibility {
  $diagnostics = New-CodexInvocationDiagnostics
  $profile = New-CodexInvocationProfileSummary
  $classification = Get-PreviousRetryClassification
  [pscustomobject]@{
    schema = "skybridge.managed_mode_codex_invocation_compatibility.v1"
    pilot_id = $PilotId
    diagnostics = $diagnostics
    profile = $profile
    previous_retry_classification = $classification
    compatible = ($profile.selected_invocation_profile -eq "profile_workspace_write_workdir")
    token_printed = $false
  }
}

function New-ReplacementRetryReadiness {
  $classification = Get-PreviousRetryClassification
  $profile = New-CodexInvocationProfileSummary
  $gate = New-ApplyGate
  $runner = Get-RunnerLockState
  $git = Get-GitState
  $blockers = New-Object System.Collections.Generic.List[string]
  if ($classification.classification -ne "invocation_failed_no_mutation") { $blockers.Add("previous_retry_not_invocation_failed_no_mutation") | Out-Null }
  if ($classification.replacement_retry_count -ne 0) { $blockers.Add("replacement_retry_budget_exhausted") | Out-Null }
  if ($profile.selected_invocation_profile -ne "profile_workspace_write_workdir") { $blockers.Add("workspace_write_profile_not_selected") | Out-Null }
  if ($classification.changed_files.Count -ne 0) { $blockers.Add("prior_retry_changed_files_present") | Out-Null }
  if ($classification.open_pilot_pr_count -ne 0 -or $classification.pr_created -or $classification.pr_url_present) { $blockers.Add("prior_retry_pr_present") | Out-Null }
  if ($classification.executor_evidence_exists) { $blockers.Add("prior_executor_evidence_present") | Out-Null }
  if ($classification.finalizer_evidence_exists) { $blockers.Add("prior_finalizer_evidence_present") | Out-Null }
  if ($classification.raw_or_secret_artifacts_present) { $blockers.Add("prior_raw_or_secret_artifacts_present") | Out-Null }
  if ($classification.prompt_persisted -or $classification.transcript_persisted -or $classification.stdout_persisted -or $classification.stderr_persisted -or $classification.raw_logs_persisted) { $blockers.Add("prior_raw_artifact_flags_present") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if ($gate.active_tasks -ne 0) { $blockers.Add("active_tasks_present") | Out-Null }
  if ($gate.stale_leases -ne 0) { $blockers.Add("stale_leases_present") | Out-Null }
  if ($git.branch -ne "main" -or -not $git.clean) { $blockers.Add("replacement_retry_requires_clean_main") | Out-Null }

  [pscustomobject]@{
    schema = "skybridge.managed_mode_replacement_retry_readiness.v1"
    pilot_id = $PilotId
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = $WorkerId
    task_type = "docs/local-smoke"
    risk = "low"
    target_path = "docs/managed-mode-pilot-orientation.md"
    previous_retry_classification = $classification.classification
    selected_invocation_profile = $profile.selected_invocation_profile
    can_run_replacement_retry = ($blockers.Count -eq 0)
    replacement_retry_count = $classification.replacement_retry_count
    max_replacement_retries = 1
    active_tasks = $gate.active_tasks
    stale_leases = $gate.stale_leases
    runner_lock = $runner.runner_lock_status
    open_pilot_pr_count = $classification.open_pilot_pr_count
    executor_evidence_exists = $classification.executor_evidence_exists
    finalizer_evidence_exists = $classification.finalizer_evidence_exists
    general_bounded_queue_apply_enabled = $false
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Get-PilotTaskPrSnapshot {
  param($ExecutorEvidence)
  if ($SimulateFinalizerMergedPr) {
    return [pscustomobject]@{
      exists = $true
      number = 140
      url = if ($ExecutorEvidence -and $ExecutorEvidence.pr_url) { [string]$ExecutorEvidence.pr_url } else { "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140" }
      title = "Task managed-mode-pilot-208-workunit-001: Managed Mode Pilot 208 docs/local-smoke"
      state = "MERGED"
      merged = $true
      merged_at = "2026-06-10T06:49:02Z"
      merge_commit = "347f38d2e630a44390957827bbda2f94e529f2a5"
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
    $raw = gh pr view $number --json number,url,title,state,mergedAt,mergeCommit,baseRefName,headRefName,files 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($raw | Out-String).Trim())) { throw "gh pr view failed" }
    $pr = $raw | ConvertFrom-Json
    [pscustomobject]@{
      exists = $true
      number = [int]$pr.number
      url = [string]$pr.url
      title = [string]$pr.title
      state = [string]$pr.state
      merged = (-not [string]::IsNullOrWhiteSpace([string]$pr.mergedAt))
      merged_at = if ([string]::IsNullOrWhiteSpace([string]$pr.mergedAt)) { $null } else { [string]$pr.mergedAt }
      merge_commit = if ($pr.mergeCommit -and $pr.mergeCommit.oid) { [string]$pr.mergeCommit.oid } else { $null }
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
  $finalizerEvidenceExists = Test-Path -LiteralPath (Get-PilotFinalizerEvidencePath) -PathType Leaf
  $blockers = New-Object System.Collections.Generic.List[string]

  if ($PilotId -ne "managed-mode-pilot-208") { $blockers.Add("pilot_id_not_explicitly_authorized") | Out-Null }
  if ($finalizerEvidenceExists) { $blockers.Add("managed_mode_pilot_already_completed") | Out-Null }
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
  $replacementRetryPath = Get-PilotReplacementRetryResultPath
  $finalizerEvidencePath = Get-PilotFinalizerEvidencePath
  $finalizerExists = Test-Path -LiteralPath $finalizerEvidencePath -PathType Leaf
  $executorEvidence = Read-PilotExecutorEvidence
  $replacementRetry = Read-SafeJsonFile -Path $replacementRetryPath
  $prSnapshot = Get-PilotTaskPrSnapshot -ExecutorEvidence $executorEvidence
  $runner = Get-RunnerLockState
  $fileScan = Test-SafeStateDirFiles
  $blockers = New-Object System.Collections.Generic.List[string]
  $changedFiles = @()
  $replacementRetryChangedFiles = @()
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

  if (-not $replacementRetry) {
    $blockers.Add("replacement_retry_result_missing") | Out-Null
  } else {
    if (-not (Test-SafeJsonObject $replacementRetry)) {
      $blockers.Add("replacement_retry_result_unsafe") | Out-Null
      $noRawArtifacts = $false
    }
    $replacementRetryChangedFiles = @(Get-ObjectStringArray -Object $replacementRetry -Name "changed_files" | ForEach-Object { ConvertTo-NormalizedGitPath -Path $_ })
    if ([string]$replacementRetry.final_state -ne "held_waiting_human_pr_review") { $blockers.Add("replacement_retry_final_state_mismatch") | Out-Null }
    if ([string]$replacementRetry.pr_url -ne "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/140") { $blockers.Add("replacement_retry_pr_url_mismatch") | Out-Null }
    if ($replacementRetry.token_printed -ne $false) { $blockers.Add("replacement_retry_token_printed_not_false") | Out-Null }
  }

  $expectedChangedFiles = @(Get-PilotExpectedChangedFiles)
  $normalizedChangedFiles = @($changedFiles | ForEach-Object { ConvertTo-NormalizedGitPath -Path $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  $normalizedReplacementChangedFiles = @($replacementRetryChangedFiles | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  if ($normalizedChangedFiles.Count -ne $expectedChangedFiles.Count -or @($normalizedChangedFiles | Where-Object { $expectedChangedFiles -notcontains $_ }).Count -gt 0) {
    $blockers.Add("pilot_changed_files_mismatch") | Out-Null
  }
  if ($normalizedReplacementChangedFiles.Count -gt 0 -and ($normalizedReplacementChangedFiles.Count -ne $expectedChangedFiles.Count -or @($normalizedReplacementChangedFiles | Where-Object { $expectedChangedFiles -notcontains $_ }).Count -gt 0)) {
    $blockers.Add("replacement_retry_changed_files_mismatch") | Out-Null
  }

  if (-not $prSnapshot.exists) { $blockers.Add("pilot_task_pr_missing") | Out-Null }
  if ($prSnapshot.exists -and -not $prSnapshot.merged) { $blockers.Add("pilot_task_pr_not_merged") | Out-Null }
  if ($prSnapshot.base_ref -and $prSnapshot.base_ref -ne "main") { $blockers.Add("pilot_task_pr_base_not_main") | Out-Null }
  if ($prSnapshot.exists -and $prSnapshot.number -ne 140 -and -not $SimulateFinalizerMergedPr) { $blockers.Add("pilot_task_pr_number_mismatch") | Out-Null }
  if ($prSnapshot.exists) {
    $prChangedFiles = @($prSnapshot.changed_files | ForEach-Object { ConvertTo-NormalizedGitPath -Path $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    foreach ($file in $prChangedFiles) {
      if (-not (Test-PathAllowedForPilot -Path $file)) { $blockers.Add("task_pr_path_allowlist_violation:$file") | Out-Null }
    }
    if ($prChangedFiles.Count -ne $expectedChangedFiles.Count -or @($prChangedFiles | Where-Object { $expectedChangedFiles -notcontains $_ }).Count -gt 0) {
      $blockers.Add("task_pr_changed_files_mismatch") | Out-Null
    }
  }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (-not $fileScan.safe) {
    $blockers.Add("raw_or_secret_artifacts_present") | Out-Null
    $noRawArtifacts = $false
  }

  $completed = ($finalizerExists -or ($blockers.Count -eq 0))
  [pscustomobject]@{
    schema = "skybridge.managed_mode_pilot_finalizer_state.v1"
    pilot_id = $PilotId
    mode = "managed_mode_v1_pilot"
    state = if ($finalizerExists) { "managed_mode_pilot_completed" } elseif ($blockers.Count -eq 0) { "ready_to_finalize" } else { "held_waiting_human_pr_review" }
    final_state = if ($completed) { "managed_mode_pilot_completed" } else { "held_waiting_human_pr_review" }
    executor_evidence_path = if (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) { ConvertTo-ShortPath $executorEvidencePath } else { $null }
    replacement_retry_result_path = if (Test-Path -LiteralPath $replacementRetryPath -PathType Leaf) { ConvertTo-ShortPath $replacementRetryPath } else { $null }
    finalizer_evidence_path = if ($finalizerExists) { ConvertTo-ShortPath $finalizerEvidencePath } else { $null }
    task_pr = $prSnapshot
    changed_files = @($normalizedChangedFiles)
    replacement_retry_changed_files = @($normalizedReplacementChangedFiles)
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
    replacement_retry_result_path = $State.replacement_retry_result_path
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
      next_safe_action = "plan next managed-mode repeatability goal"
      token_printed = $false
    }
    evidence_path = ConvertTo-ShortPath $finalizerEvidencePath
    report_path = ConvertTo-ShortPath (Get-PilotFinalizerReportPath)
    next_safe_action = "plan next managed-mode repeatability goal"
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
  $renewal = New-RenewedAuthorizationState
  if ($RenewedAuthorization -or $RequireRenewedAuthorization) {
    if (-not $renewal.can_run_renewed_apply) {
      return [pscustomobject]@{
        ok = $false
        schema = "skybridge.bounded_queue_apply_result.v1"
        pilot_id = $PilotId
        mode = "renewed_pilot_apply_blocked"
        final_state = "pilot_gate_blocked"
        renewed_authorization = [bool]$RenewedAuthorization
        renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
        prior_attempt_state = $renewal.prior_attempt_state
        prior_attempt_had_task_pr = $renewal.prior_attempt_had_task_pr
        prior_attempt_had_executor_evidence = $renewal.prior_attempt_had_executor_evidence
        prior_attempt_had_raw_artifacts = $renewal.prior_attempt_had_raw_artifacts
        renewed_attempt_count = $renewal.renewed_attempt_count
        task_created = $false
        task_claimed = $false
        codex_execution_started = $false
        pr_created = $false
        blockers = @($renewal.blockers)
        token_printed = $false
      }
    }
  }
  if ($SimulateApply) {
    return [pscustomobject]@{
      ok = $true
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = if ($RenewedAuthorization) { "simulated_renewed_pilot_apply_no_mutation" } else { "simulated_pilot_apply_no_mutation" }
      final_state = "held_waiting_human_pr_review"
      renewed_authorization = [bool]$RenewedAuthorization
      renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
      prior_attempt_state = $renewal.prior_attempt_state
      prior_attempt_had_task_pr = $renewal.prior_attempt_had_task_pr
      prior_attempt_had_executor_evidence = $renewal.prior_attempt_had_executor_evidence
      prior_attempt_had_raw_artifacts = $renewal.prior_attempt_had_raw_artifacts
      renewed_attempt_count = $renewal.renewed_attempt_count
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
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory $codex.working_directory -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  if (-not $execution.ok) {
    git switch main *> $null
    $failure = [pscustomobject]@{
      ok = $false
      schema = "skybridge.bounded_queue_apply_result.v1"
      pilot_id = $PilotId
      mode = if ($RenewedAuthorization) { "renewed_controlled_failure" } else { "controlled_failure" }
      final_state = "held_no_execution_executor_failed"
      renewed_authorization = [bool]$RenewedAuthorization
      renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
      prior_attempt_state = $renewal.prior_attempt_state
      prior_attempt_had_task_pr = $renewal.prior_attempt_had_task_pr
      prior_attempt_had_executor_evidence = $renewal.prior_attempt_had_executor_evidence
      prior_attempt_had_raw_artifacts = $renewal.prior_attempt_had_raw_artifacts
      renewed_attempt_count = $renewal.renewed_attempt_count
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      launcher_metadata = $codex.metadata
      pr_created = $false
      exit_code = $execution.exit_code
      timed_out = $execution.timed_out
      elapsed_seconds = $execution.elapsed_seconds
      timeout_minutes = $execution.timeout_minutes
      stdout_chars_discarded = $execution.stdout_chars_discarded
      stderr_chars_discarded = $execution.stderr_chars_discarded
      stdout_persisted = $false
      stderr_persisted = $false
      prompt_persisted = $false
      transcript_persisted = $false
      token_printed = $false
    }
    $failureJson = $failure | ConvertTo-Json -Depth 60
    if (Test-SecretLookingText $failureJson) { throw "Secret-looking pilot failure result detected." }
    $failureJson | Set-Content -LiteralPath (Get-PilotResultPath) -Encoding UTF8
    return $failure
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
    command_class = $codex.metadata.command_class
    launcher_metadata = $codex.metadata
    changed_files = @($changedFiles)
    file_evidence = @($fileEvidence)
    prompt_sha256 = $promptHash
    renewed_authorization = [bool]$RenewedAuthorization
    renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
    prior_attempt_state = $renewal.prior_attempt_state
    prior_attempt_had_task_pr = $renewal.prior_attempt_had_task_pr
    prior_attempt_had_executor_evidence = $renewal.prior_attempt_had_executor_evidence
    prior_attempt_had_raw_artifacts = $renewal.prior_attempt_had_raw_artifacts
    renewed_attempt_count = $renewal.renewed_attempt_count
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
    renewed_authorization = [bool]$RenewedAuthorization
    renewed_authorization_reason = if ([string]::IsNullOrWhiteSpace($RenewedAuthorizationReason)) { $null } else { $RenewedAuthorizationReason }
    prior_attempt_state = $renewal.prior_attempt_state
    prior_attempt_had_task_pr = $renewal.prior_attempt_had_task_pr
    prior_attempt_had_executor_evidence = $renewal.prior_attempt_had_executor_evidence
    prior_attempt_had_raw_artifacts = $renewal.prior_attempt_had_raw_artifacts
    renewed_attempt_count = $renewal.renewed_attempt_count
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

function Write-SafeRetryResult {
  param($Result)
  $json = $Result | ConvertTo-Json -Depth 80
  if (Test-SecretLookingText $json) { throw "Secret-looking retry result detected." }
  New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
  $json | Set-Content -LiteralPath (Get-PilotRetryResultPath) -Encoding UTF8
}

function Write-SafeReplacementRetryResult {
  param($Result)
  $json = $Result | ConvertTo-Json -Depth 100
  if (Test-SecretLookingText $json) { throw "Secret-looking replacement retry result detected." }
  New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
  $json | Set-Content -LiteralPath (Get-PilotReplacementRetryResultPath) -Encoding UTF8
}

function Invoke-RetryApply {
  $readiness = New-RetryReadiness
  if (-not $readiness.can_retry) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = "retry_apply_blocked"
      final_state = "retry_blocked"
      prior_state = $readiness.prior_state
      retry_attempt = 0
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @($readiness.blockers)
      token_printed = $false
    }
  }

  if ($SimulateRetryApply) {
    $finalState = switch ($SimulateRetryOutcome) {
      "success" { "held_waiting_human_pr_review" }
      "timeout" { "pilot_failed_timeout_retry_exhausted" }
      "no-changes" { "pilot_failed_retry_exhausted" }
      "bad-path" { "pilot_failed_retry_exhausted" }
    }
    return [pscustomobject]@{
      ok = ($SimulateRetryOutcome -eq "success")
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = "simulated_retry_apply_no_mutation"
      final_state = $finalState
      prior_state = $readiness.prior_state
      retry_authorization = [bool]$RetryAuthorization
      retry_authorization_reason = if ([string]::IsNullOrWhiteSpace($RetryAuthorizationReason)) { $null } else { $RetryAuthorizationReason }
      retry_attempt = 1
      retry_count = 1
      max_retries = 1
      workunit_id = "managed-mode-pilot-208-workunit-001"
      task_id = "managed-mode-pilot-208-task-001"
      worker_id = "laptop-zenbookduo"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = ($SimulateRetryOutcome -eq "success")
      pr_count = if ($SimulateRetryOutcome -eq "success") { 1 } else { 0 }
      changed_files = if ($SimulateRetryOutcome -eq "success") { @("docs/managed-mode-pilot-orientation.md") } elseif ($SimulateRetryOutcome -eq "bad-path") { @("apps/server/src/index.ts") } else { @() }
      timed_out = ($SimulateRetryOutcome -eq "timeout")
      auto_merge_enabled = $false
      no_mutation = $true
      token_printed = $false
    }
  }

  $git = Get-GitState
  if ($git.branch -ne "main" -or -not $git.clean) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = "retry_apply_blocked"
      final_state = "retry_blocked"
      prior_state = $readiness.prior_state
      retry_attempt = 0
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("retry_requires_clean_main")
      token_printed = $false
    }
  }

  $codex = Get-CodexCommand
  if (-not $codex) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = "retry_apply_blocked"
      final_state = "retry_blocked"
      prior_state = $readiness.prior_state
      retry_attempt = 0
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("codex_cli_missing")
      token_printed = $false
    }
  }

  $branch = "ai/managed-mode-pilot/managed-mode-pilot-208-retry-001"
  New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch retry branch failed." }

  $prompt = New-RetryPilotPrompt
  $promptHash = Get-Sha256Text -Text $prompt
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory $codex.working_directory -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  $changedFilesAfterExecution = @(Get-ChangedFiles)
  if (-not $execution.ok) {
    if ($changedFilesAfterExecution.Count -eq 0) { git switch main *> $null }
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = if ($execution.timed_out) { "retry_timeout" } else { "retry_controlled_failure" }
      final_state = if ($execution.timed_out) { "pilot_failed_timeout_retry_exhausted" } else { "pilot_failed_retry_exhausted" }
      prior_state = $readiness.prior_state
      retry_authorization = [bool]$RetryAuthorization
      retry_authorization_reason = $RetryAuthorizationReason
      retry_attempt = 1
      retry_count = 1
      max_retries = 1
      workunit_id = "managed-mode-pilot-208-workunit-001"
      task_id = "managed-mode-pilot-208-task-001"
      worker_id = "laptop-zenbookduo"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      pr_count = 0
      changed_files = @($changedFilesAfterExecution)
      timed_out = $execution.timed_out
      exit_code = $execution.exit_code
      elapsed_seconds = $execution.elapsed_seconds
      timeout_minutes = $execution.timeout_minutes
      launcher_metadata = $codex.metadata
      stdout_chars_discarded = $execution.stdout_chars_discarded
      stderr_chars_discarded = $execution.stderr_chars_discarded
      stdout_persisted = $false
      stderr_persisted = $false
      prompt_persisted = $false
      transcript_persisted = $false
      token_printed = $false
    }
    Write-SafeRetryResult -Result $result
    return $result
  }

  $changedFiles = @(Get-ChangedFiles)
  if ($changedFiles.Count -lt 1) {
    git switch main *> $null
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_pilot_retry_result.v1"
      pilot_id = $PilotId
      mode = "retry_no_changes"
      final_state = "pilot_failed_retry_exhausted"
      prior_state = $readiness.prior_state
      retry_authorization = [bool]$RetryAuthorization
      retry_authorization_reason = $RetryAuthorizationReason
      retry_attempt = 1
      retry_count = 1
      max_retries = 1
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      changed_files = @()
      token_printed = $false
    }
    Write-SafeRetryResult -Result $result
    return $result
  }
  foreach ($file in $changedFiles) {
    if (-not (Test-PathAllowedForPilot -Path $file)) {
      $result = [pscustomobject]@{
        ok = $false
        schema = "skybridge.managed_mode_pilot_retry_result.v1"
        pilot_id = $PilotId
        mode = "retry_disallowed_path"
        final_state = "pilot_failed_retry_exhausted"
        prior_state = $readiness.prior_state
        retry_authorization = [bool]$RetryAuthorization
        retry_authorization_reason = $RetryAuthorizationReason
        retry_attempt = 1
        retry_count = 1
        max_retries = 1
        task_created = $true
        task_claimed = $true
        codex_execution_started = $true
        codex_execution_count = 1
        pr_created = $false
        changed_files = @($changedFiles)
        blockers = @("disallowed_retry_changed_path:$file")
        token_printed = $false
      }
      Write-SafeRetryResult -Result $result
      return $result
    }
  }
  foreach ($file in $changedFiles) {
    git add -- $file *> $null
    if ($LASTEXITCODE -ne 0) { throw "git add failed for $file" }
  }
  git commit -m "docs: add managed mode pilot retry orientation" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $bodyPath = Join-Path (Get-StateDirPath) "task-pr-body.md"
  $body = @"
## Summary

Managed Mode Pilot 208 Retry docs/local-smoke task.

## Safety

- Pilot id: `managed-mode-pilot-208`
- Workunit id: `managed-mode-pilot-208-workunit-001`
- Task id: `managed-mode-pilot-208-task-001`
- Worker: `laptop-zenbookduo`
- Retry attempt: `1`
- Task type: `docs/local-smoke`
- Changed files: $($changedFiles -join ", ")
- No raw prompt, transcript, stdout, stderr, worker log or CI log is included.
- No auto-merge requested.
- token_printed=false
"@
  if (Test-SecretLookingText $body) { throw "Secret-looking retry PR body detected." }
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8
  $prOutput = gh pr create --title "Task managed-mode-pilot-208-workunit-001: Managed Mode Pilot 208 Retry docs/local-smoke" --body-file $bodyPath --base main --head $branch
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
    mode = "managed_mode_v1_pilot_retry"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    command_class = $codex.metadata.command_class
    launcher_metadata = $codex.metadata
    changed_files = @($changedFiles)
    file_evidence = @($fileEvidence)
    prompt_sha256 = $promptHash
    retry_attempt = 1
    retry_count = 1
    max_retries = 1
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
  $evidenceJson = $evidence | ConvertTo-Json -Depth 80
  if (Test-SecretLookingText $evidenceJson) { throw "Secret-looking retry evidence detected." }
  $evidenceJson | Set-Content -LiteralPath (Get-PilotEvidencePath) -Encoding UTF8
  $result = [pscustomobject]@{
    ok = $true
    schema = "skybridge.managed_mode_pilot_retry_result.v1"
    pilot_id = $PilotId
    mode = "retry_apply"
    final_state = "held_waiting_human_pr_review"
    prior_state = $readiness.prior_state
    retry_authorization = [bool]$RetryAuthorization
    retry_authorization_reason = $RetryAuthorizationReason
    retry_attempt = 1
    retry_count = 1
    max_retries = 1
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
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
  Write-SafeRetryResult -Result $result
  git switch main *> $null
  return $result
}

function Test-PathAllowedForReplacementRetry {
  param([string]$Path)
  $normalized = $Path.Replace("\", "/")
  return ($normalized -eq "docs/managed-mode-pilot-orientation.md")
}

function Invoke-ReplacementRetryApply {
  $readiness = New-ReplacementRetryReadiness
  if (-not $readiness.can_run_replacement_retry -or -not $ReplacementRetryAuthorization -or [string]::IsNullOrWhiteSpace($ReplacementRetryAuthorizationReason)) {
    $blockers = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($readiness.blockers)) { $blockers.Add([string]$item) | Out-Null }
    if (-not $ReplacementRetryAuthorization) { $blockers.Add("replacement_retry_authorization_required") | Out-Null }
    if ([string]::IsNullOrWhiteSpace($ReplacementRetryAuthorizationReason)) { $blockers.Add("replacement_retry_authorization_reason_required") | Out-Null }
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_replacement_retry_result.v1"
      pilot_id = $PilotId
      mode = "replacement_retry_blocked"
      final_state = "replacement_retry_blocked"
      previous_retry_classification = $readiness.previous_retry_classification
      selected_invocation_profile = $readiness.selected_invocation_profile
      replacement_retry_attempt = 0
      replacement_retry_count = $readiness.replacement_retry_count
      max_replacement_retries = 1
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @($blockers | Select-Object -Unique)
      token_printed = $false
    }
  }

  if ($SimulateReplacementRetryApply) {
    $changed = if ($SimulateReplacementRetryOutcome -eq "success") { @("docs/managed-mode-pilot-orientation.md") } elseif ($SimulateReplacementRetryOutcome -eq "bad-path") { @("apps/server/src/index.ts") } else { @() }
    $result = [pscustomobject]@{
      ok = ($SimulateReplacementRetryOutcome -eq "success")
      schema = "skybridge.managed_mode_replacement_retry_result.v1"
      pilot_id = $PilotId
      mode = "simulated_replacement_retry_no_mutation"
      final_state = switch ($SimulateReplacementRetryOutcome) {
        "success" { "held_waiting_human_pr_review" }
        "timeout" { "pilot_failed_replacement_retry_timeout" }
        default { "pilot_failed_replacement_retry_failed" }
      }
      previous_retry_classification = $readiness.previous_retry_classification
      selected_invocation_profile = $readiness.selected_invocation_profile
      replacement_retry_authorization = [bool]$ReplacementRetryAuthorization
      replacement_retry_authorization_reason = $ReplacementRetryAuthorizationReason
      replacement_retry_attempt = 1
      replacement_retry_count = 1
      max_replacement_retries = 1
      workunit_id = "managed-mode-pilot-208-workunit-001"
      task_id = "managed-mode-pilot-208-task-001"
      worker_id = "laptop-zenbookduo"
      task_type = "docs/local-smoke"
      target_path = "docs/managed-mode-pilot-orientation.md"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = ($SimulateReplacementRetryOutcome -eq "success")
      pr_count = if ($SimulateReplacementRetryOutcome -eq "success") { 1 } else { 0 }
      changed_files = @($changed)
      timed_out = ($SimulateReplacementRetryOutcome -eq "timeout")
      prompt_persisted = $false
      transcript_persisted = $false
      stdout_persisted = $false
      stderr_persisted = $false
      raw_logs_persisted = $false
      auto_merge_enabled = $false
      no_mutation = $true
      token_printed = $false
    }
    Write-SafeReplacementRetryResult -Result $result
    return $result
  }

  $codex = Get-CodexCommand -ProfileId "profile_workspace_write_workdir"
  if (-not $codex) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_replacement_retry_result.v1"
      pilot_id = $PilotId
      mode = "replacement_retry_blocked"
      final_state = "replacement_retry_blocked"
      previous_retry_classification = $readiness.previous_retry_classification
      selected_invocation_profile = "profile_disabled_unknown"
      replacement_retry_attempt = 0
      task_created = $false
      task_claimed = $false
      codex_execution_started = $false
      pr_created = $false
      blockers = @("codex_cli_missing")
      token_printed = $false
    }
  }

  $branch = "ai/managed-mode-pilot/managed-mode-pilot-208-replacement-retry-001"
  New-Item -ItemType Directory -Path (Get-StateDirPath) -Force | Out-Null
  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch replacement retry branch failed." }

  $prompt = New-RetryPilotPrompt
  $promptHash = Get-Sha256Text -Text $prompt
  $execution = Invoke-SilentProcess -FilePath $codex.file_path -ArgumentList ([string[]]$codex.argument_list) -WorkingDirectory $codex.working_directory -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  $changedFilesAfterExecution = @(Get-ChangedFiles)
  if (-not $execution.ok) {
    if ($changedFilesAfterExecution.Count -eq 0) { git switch main *> $null }
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_replacement_retry_result.v1"
      pilot_id = $PilotId
      mode = if ($execution.timed_out) { "replacement_retry_timeout" } else { "replacement_retry_controlled_failure" }
      final_state = if ($execution.timed_out) { "pilot_failed_replacement_retry_timeout" } else { "pilot_failed_replacement_retry_failed" }
      previous_retry_classification = $readiness.previous_retry_classification
      selected_invocation_profile = $codex.metadata.command_profile_id
      replacement_retry_authorization = [bool]$ReplacementRetryAuthorization
      replacement_retry_authorization_reason = $ReplacementRetryAuthorizationReason
      replacement_retry_attempt = 1
      replacement_retry_count = 1
      max_replacement_retries = 1
      workunit_id = "managed-mode-pilot-208-workunit-001"
      task_id = "managed-mode-pilot-208-task-001"
      worker_id = "laptop-zenbookduo"
      task_type = "docs/local-smoke"
      target_path = "docs/managed-mode-pilot-orientation.md"
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      pr_count = 0
      changed_files = @($changedFilesAfterExecution)
      timed_out = $execution.timed_out
      exit_code = $execution.exit_code
      elapsed_seconds = $execution.elapsed_seconds
      timeout_minutes = $execution.timeout_minutes
      launcher_metadata = $codex.metadata
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
    Write-SafeReplacementRetryResult -Result $result
    return $result
  }

  $changedFiles = @(Get-ChangedFiles)
  if ($changedFiles.Count -lt 1) {
    git switch main *> $null
    $result = [pscustomobject]@{
      ok = $false
      schema = "skybridge.managed_mode_replacement_retry_result.v1"
      pilot_id = $PilotId
      mode = "replacement_retry_no_changes"
      final_state = "pilot_failed_replacement_retry_failed"
      previous_retry_classification = $readiness.previous_retry_classification
      selected_invocation_profile = $codex.metadata.command_profile_id
      replacement_retry_authorization = [bool]$ReplacementRetryAuthorization
      replacement_retry_authorization_reason = $ReplacementRetryAuthorizationReason
      replacement_retry_attempt = 1
      replacement_retry_count = 1
      max_replacement_retries = 1
      task_created = $true
      task_claimed = $true
      codex_execution_started = $true
      codex_execution_count = 1
      pr_created = $false
      changed_files = @()
      token_printed = $false
    }
    Write-SafeReplacementRetryResult -Result $result
    return $result
  }
  foreach ($file in $changedFiles) {
    if (-not (Test-PathAllowedForReplacementRetry -Path $file)) {
      $result = [pscustomobject]@{
        ok = $false
        schema = "skybridge.managed_mode_replacement_retry_result.v1"
        pilot_id = $PilotId
        mode = "replacement_retry_disallowed_path"
        final_state = "pilot_failed_replacement_retry_failed"
        previous_retry_classification = $readiness.previous_retry_classification
        selected_invocation_profile = $codex.metadata.command_profile_id
        replacement_retry_authorization = [bool]$ReplacementRetryAuthorization
        replacement_retry_authorization_reason = $ReplacementRetryAuthorizationReason
        replacement_retry_attempt = 1
        replacement_retry_count = 1
        max_replacement_retries = 1
        task_created = $true
        task_claimed = $true
        codex_execution_started = $true
        codex_execution_count = 1
        pr_created = $false
        changed_files = @($changedFiles)
        blockers = @("disallowed_replacement_retry_changed_path:$file")
        token_printed = $false
      }
      Write-SafeReplacementRetryResult -Result $result
      return $result
    }
  }
  foreach ($file in $changedFiles) {
    git add -- $file *> $null
    if ($LASTEXITCODE -ne 0) { throw "git add failed for $file" }
  }
  git commit -m "docs: add managed mode pilot replacement orientation" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $bodyPath = Join-Path (Get-StateDirPath) "task-pr-body.md"
  $body = @"
## Summary

Managed Mode Pilot 208 Replacement Retry docs/local-smoke task.

## Safety

- Pilot id: `managed-mode-pilot-208`
- Workunit id: `managed-mode-pilot-208-workunit-001`
- Task id: `managed-mode-pilot-208-task-001`
- Worker: `laptop-zenbookduo`
- Replacement retry attempt: `1`
- Task type: `docs/local-smoke`
- Changed files: $($changedFiles -join ", ")
- No raw prompt, transcript, stdout, stderr, worker log or CI log is included.
- No auto-merge requested.
- token_printed=false
"@
  if (Test-SecretLookingText $body) { throw "Secret-looking replacement retry PR body detected." }
  Set-Content -LiteralPath $bodyPath -Value $body -Encoding UTF8
  $prOutput = gh pr create --title "Managed Mode Pilot 208 Replacement Retry: Task managed-mode-pilot-208-workunit-001" --body-file $bodyPath --base main --head $branch
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
    mode = "managed_mode_v1_pilot_replacement_retry"
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    task_type = "docs/local-smoke"
    command_class = $codex.metadata.command_class
    launcher_metadata = $codex.metadata
    changed_files = @($changedFiles)
    file_evidence = @($fileEvidence)
    prompt_sha256 = $promptHash
    replacement_retry_attempt = 1
    replacement_retry_count = 1
    max_replacement_retries = 1
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    raw_logs_persisted = $false
    task_created = $true
    task_claimed = $true
    codex_execution_count = 1
    pr_url = $prUrl
    pr_count = 1
    auto_merge_enabled = $false
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  }
  $evidenceJson = $evidence | ConvertTo-Json -Depth 100
  if (Test-SecretLookingText $evidenceJson) { throw "Secret-looking replacement retry evidence detected." }
  $evidenceJson | Set-Content -LiteralPath (Get-PilotEvidencePath) -Encoding UTF8
  $result = [pscustomobject]@{
    ok = $true
    schema = "skybridge.managed_mode_replacement_retry_result.v1"
    pilot_id = $PilotId
    mode = "replacement_retry_apply"
    final_state = "held_waiting_human_pr_review"
    previous_retry_classification = $readiness.previous_retry_classification
    selected_invocation_profile = $codex.metadata.command_profile_id
    replacement_retry_authorization = [bool]$ReplacementRetryAuthorization
    replacement_retry_authorization_reason = $ReplacementRetryAuthorizationReason
    replacement_retry_attempt = 1
    replacement_retry_count = 1
    max_replacement_retries = 1
    workunit_id = "managed-mode-pilot-208-workunit-001"
    task_id = "managed-mode-pilot-208-task-001"
    worker_id = "laptop-zenbookduo"
    task_type = "docs/local-smoke"
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
    result_path = ConvertTo-ShortPath (Get-PilotReplacementRetryResultPath)
    auto_merge_enabled = $false
    token_printed = $false
  }
  Write-SafeReplacementRetryResult -Result $result
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
      "skybridge.managed_mode_pilot_renewed_authorization_state.v1",
      "skybridge.managed_mode_pilot_timeout_state.v1",
      "skybridge.managed_mode_pilot_retry_policy.v1",
      "skybridge.managed_mode_pilot_retry_readiness.v1",
      "skybridge.managed_mode_pilot_retry_result.v1",
      "skybridge.managed_mode_codex_invocation_diagnostics.v1",
      "skybridge.managed_mode_codex_invocation_profile.v1",
      "skybridge.managed_mode_codex_invocation_classification.v1",
      "skybridge.managed_mode_replacement_retry_readiness.v1",
      "skybridge.managed_mode_replacement_retry_result.v1",
      "skybridge.managed_mode_changed_files_preview.v1",
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
  $finalizerPath = Get-PilotFinalizerEvidencePath
  $finalizerCompleted = Test-Path -LiteralPath $finalizerPath -PathType Leaf
  [pscustomobject]@{
    schema = "skybridge.managed_mode_v1_safe_summary.v1"
    pilot_id = $PilotId
    managed_mode_v1 = "pilot only"
    managed_mode_pilot_state = if ($finalizerCompleted) { "managed_mode_pilot_completed" } else { (New-PilotState).state }
    general_apply = "disabled"
    one_workunit_pilot_possible_only_after_gate = $true
    can_start_managed_mode = $false
    can_run_pilot = $readiness.can_run_pilot
    general_bounded_queue_apply_enabled = $false
    pilot_bounded_queue_apply_enabled = $gate.pilot_bounded_queue_apply_enabled
    launcher_metadata = $gate.launcher_metadata
    selected_invocation_profile = if ($gate.launcher_metadata) { $gate.launcher_metadata.command_profile_id } else { "profile_disabled_unknown" }
    max_workunits = $MaxWorkunits
    max_tasks = $MaxTasks
    max_claims = $MaxClaims
    max_codex_executions = $MaxCodexExecutions
    max_prs = $MaxPrs
    task_created = $false
    task_claimed = $false
    task_executed = $false
    pr_created = $false
    no_next_execution_authorized = $finalizerCompleted
    next_safe_action = if ($finalizerCompleted) { "plan next managed-mode repeatability goal" } else { "complete managed-mode pilot finalizer after human PR review" }
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
  "timeout-state" { New-TimeoutState }
  "changed-files-preview" { New-ChangedFilesPreview }
  "retry-readiness" { New-RetryReadiness }
  "retry-preview" { [pscustomobject]@{ schema = "skybridge.managed_mode_pilot_retry_preview.v1"; readiness = New-RetryReadiness; request = New-PilotPlan; retry_target_path = "docs/managed-mode-pilot-orientation.md"; no_mutation = $true; token_printed = $false } }
  "retry-apply" { Invoke-RetryApply }
  "codex-invocation-diagnostics" { New-CodexInvocationDiagnostics }
  "codex-invocation-profile" { New-CodexInvocationProfileSummary }
  "codex-invocation-compatibility" { New-CodexInvocationCompatibility }
  "codex-invocation-safe-summary" { [pscustomobject]@{ schema = "skybridge.managed_mode_codex_invocation_safe_summary.v1"; diagnostics = New-CodexInvocationDiagnostics; profile = New-CodexInvocationProfileSummary; previous_retry_classification = Get-PreviousRetryClassification; general_bounded_queue_apply_enabled = $false; token_printed = $false } }
  "replacement-retry-readiness" { New-ReplacementRetryReadiness }
  "replacement-retry-preview" { [pscustomobject]@{ schema = "skybridge.managed_mode_replacement_retry_preview.v1"; readiness = New-ReplacementRetryReadiness; request = New-PilotPlan; target_path = "docs/managed-mode-pilot-orientation.md"; would_execute_codex = $true; would_create_pr_on_success = $true; no_mutation = $true; token_printed = $false } }
  "replacement-retry-apply" { Invoke-ReplacementRetryApply }
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
