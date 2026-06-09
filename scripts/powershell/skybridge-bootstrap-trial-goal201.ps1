[CmdletBinding()]
param(
  [ValidateSet("contract", "import-reviewed-goal", "start-one-preview", "start-one-gates", "start-one-apply", "one-shot-claim-gate", "one-shot-executor-gate", "sanitized-executor-contract", "sanitized-executor-gate", "sanitized-redaction-test", "codex-launcher-stdin-test", "start-one-reliability-report", "run-sanitized-executor", "worker-route", "no-start-all", "no-second-task", "pr-safety", "evidence", "clean-worktree")]
  [string]$Command = "contract",
  [string]$CampaignDir = "goals/bootstrap-trial-201",
  [string]$CampaignId = "bootstrap-trial-201",
  [string]$GoalId = "goal-201-controlled-start-one-bootstrap-trial",
  [string]$TaskType = "docs/local-smoke",
  [int]$MaxTasks = 1,
  [int]$MaxPrs = 1,
  [int]$MaxRuntimeMinutes = 30,
  [string[]]$AllowedPaths = @("README.md", "docs/**"),
  [string]$StateDir = ".agent/tmp/bootstrap-trial-201-one-shot",
  [string]$ProposedPath = "goals/proposed/proposed-goal-201-local-readme-refresh.md",
  [string]$Reason,
  [string]$MockCodexPath,
  [switch]$SimulateRawLogPersistence,
  [switch]$SimulateExistingOpenTaskPr,
  [switch]$Apply,
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

function Read-Json {
  param([string]$Path)
  Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-MetadataFromMarkdown {
  param([string]$Path)
  $raw = Get-Content -Raw -LiteralPath $Path
  $match = [regex]::Match($raw, '(?ms)```json\s*(\{.*?\})\s*```')
  if (-not $match.Success) { throw "Markdown metadata missing: $(ConvertTo-ShortPath $Path)" }
  $match.Groups[1].Value | ConvertFrom-Json
}

function Test-SecretLookingText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  return $Text -match '(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|raw_stdout|raw_stderr|raw_prompt|raw_worker_log|raw_codex_transcript'
}

function ConvertTo-RedactedText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }
  $value = $Text
  $value = $value -replace '(?i)authorization\s*[:=]\s*bearer\s+[A-Za-z0-9_.-]+', 'Authorization: [REDACTED]'
  $value = $value -replace '(?i)\bbearer\s+[A-Za-z0-9_.-]{12,}', 'Bearer [REDACTED]'
  $value = $value -replace 'sk-[A-Za-z0-9_-]{20,}', 'sk-[REDACTED]'
  $value = $value -replace 'gh[pousr]_[A-Za-z0-9_]{20,}', 'gh[REDACTED]'
  $value = $value -replace '(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----', '[REDACTED PRIVATE KEY]'
  return $value
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

function Get-GitState {
  $status = (git status --short | Out-String).Trim()
  $branch = (git branch --show-current).Trim()
  $tagExists = -not [string]::IsNullOrWhiteSpace((git tag --list v0.70.0-dev-queue-200-complete | Out-String).Trim())
  [pscustomobject]@{
    branch = $branch
    clean = [string]::IsNullOrWhiteSpace($status)
    status_short = $status
    dev_queue_200_completion_tag_present = $tagExists
    token_printed = $false
  }
}

function Get-RunnerLockState {
  $lockPaths = @(
    ".agent/locks/skybridge-edge-worker.lock.json",
    ".agent/tmp/campaign-runner/bootstrap-trial-201.lock.json",
    ".agent/tmp/campaign-runner/dev-queue-189-200.lock.json"
  )
  $present = @($lockPaths | Where-Object { Test-Path -LiteralPath (Resolve-RepoPath $_) -PathType Leaf })
  [pscustomobject]@{
    runner_lock_status = if ($present.Count -eq 0) { "none" } else { "present" }
    present_lock_count = $present.Count
    token_printed = $false
  }
}

function Get-OneShotStateDir {
  Resolve-RepoPath $StateDir
}

function Get-OneShotClaimEvidencePath {
  Join-Path (Get-OneShotStateDir) "claim-evidence.json"
}

function Get-OneShotExecutorEvidencePath {
  Join-Path (Get-OneShotStateDir) "executor-evidence.json"
}

function Get-OneShotSanitizedEvidencePath {
  Join-Path (Get-OneShotStateDir) "sanitized-executor-evidence.json"
}

function Get-OneShotTrialReportPath {
  Join-Path (Get-OneShotStateDir) "trial-report.json"
}

function ConvertTo-SafeReportPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $root = Get-RepoRoot
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return ConvertTo-ShortPath $full
  }
  return [System.IO.Path]::GetFileName($full)
}

function Get-ExpectedOneShotClaimFields {
  [pscustomobject]@{
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    worker_id = "laptop-zenbookduo"
    lease_id = "bootstrap-trial-201-lease-001"
  }
}

function Get-OneShotClaimEvidenceState {
  $path = Get-OneShotClaimEvidencePath
  $executorEvidencePath = Get-OneShotSanitizedEvidencePath
  $legacyExecutorEvidencePath = Get-OneShotExecutorEvidencePath
  $openPrs = @(Get-OpenBootstrapTaskPrs)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    return [pscustomobject]@{
      exists = $false
      valid_owned = $false
      resumable = $false
      malformed = $false
      foreign = $false
      already_executed = (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) -or (Test-Path -LiteralPath $legacyExecutorEvidencePath -PathType Leaf) -or $openPrs.Count -gt 0
      blockers = @()
      evidence = $null
      evidence_path = ConvertTo-ShortPath $path
      token_printed = $false
    }
  }
  try {
    $raw = Get-Content -Raw -LiteralPath $path
    $evidence = $raw | ConvertFrom-Json
    $expected = Get-ExpectedOneShotClaimFields
    $blockers = New-Object System.Collections.Generic.List[string]

    if (Test-SecretLookingText $raw) { $blockers.Add("secret_or_raw_log_in_claim_evidence") | Out-Null }
    if ($evidence.campaign_id -ne $expected.campaign_id) { $blockers.Add("foreign_claim_refused") | Out-Null }
    if ($evidence.goal_id -ne $expected.goal_id) { $blockers.Add("foreign_claim_refused") | Out-Null }
    if ($evidence.task_id -ne $expected.task_id) { $blockers.Add("foreign_claim_refused") | Out-Null }
    if ($evidence.worker_id -ne $expected.worker_id) { $blockers.Add("foreign_claim_refused") | Out-Null }
    if ($evidence.lease_id -ne $expected.lease_id) { $blockers.Add("malformed_claim_refused") | Out-Null }
    if ($evidence.token_printed -ne $false) { $blockers.Add("unsafe_claim_token_printed") | Out-Null }
    if ($evidence.prompt_included -ne $false) { $blockers.Add("unsafe_claim_prompt_included") | Out-Null }
    if ($evidence.raw_transcript_included -ne $false) { $blockers.Add("unsafe_claim_raw_transcript_included") | Out-Null }
    if ($evidence.raw_logs_included -ne $false) { $blockers.Add("unsafe_claim_raw_logs_included") | Out-Null }

    $executorEvidenceExists = (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) -or (Test-Path -LiteralPath $legacyExecutorEvidencePath -PathType Leaf)
    if ($executorEvidenceExists) { $blockers.Add("existing_executor_evidence_for_bootstrap_trial") | Out-Null }
    if ($openPrs.Count -gt 0) { $blockers.Add("existing_open_task_pr_for_bootstrap_trial") | Out-Null }

    $uniqueBlockers = @($blockers | Select-Object -Unique)
    $foreign = @($uniqueBlockers | Where-Object { $_ -eq "foreign_claim_refused" }).Count -gt 0
    $malformed = @($uniqueBlockers | Where-Object { $_ -ne "foreign_claim_refused" -and $_ -ne "existing_executor_evidence_for_bootstrap_trial" -and $_ -ne "existing_open_task_pr_for_bootstrap_trial" }).Count -gt 0
    $validOwned = (-not $foreign) -and (-not $malformed)
    $resumable = $validOwned -and (-not $executorEvidenceExists) -and ($openPrs.Count -eq 0)

    return [pscustomobject]@{
      exists = $true
      valid_owned = $validOwned
      resumable = $resumable
      malformed = $malformed
      foreign = $foreign
      already_executed = $executorEvidenceExists -or $openPrs.Count -gt 0
      blockers = @($uniqueBlockers)
      evidence = $evidence
      evidence_path = ConvertTo-ShortPath $path
      claim_state = if ($resumable) { "resumable_owned_claim" } elseif ($validOwned) { "claimed" } elseif ($foreign) { "foreign" } else { "malformed" }
      executor_evidence_path = if (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) { ConvertTo-ShortPath $executorEvidencePath } elseif (Test-Path -LiteralPath $legacyExecutorEvidencePath -PathType Leaf) { ConvertTo-ShortPath $legacyExecutorEvidencePath } else { $null }
      open_task_pr_count = $openPrs.Count
      token_printed = $false
    }
  } catch {
    return [pscustomobject]@{
      exists = $true
      valid_owned = $false
      resumable = $false
      malformed = $true
      foreign = $false
      already_executed = $false
      blockers = @("malformed_claim_refused")
      evidence = $null
      evidence_path = ConvertTo-ShortPath $path
      claim_state = "malformed"
      token_printed = $false
    }
  }
}

function Test-OwnedOneShotClaimEvidence {
  $state = Get-OneShotClaimEvidenceState
  return [bool]$state.valid_owned
}

function Test-BootstrapAllowedPath {
  param([string]$Path)
  $normalized = ([string]$Path).Replace("\", "/")
  return ($normalized -eq "README.md" -or $normalized -like "docs/*")
}

function Get-OpenBootstrapTaskPrs {
  if ($SimulateExistingOpenTaskPr) {
    return @([pscustomobject]@{
      number = 201001
      url = "https://github.com/local/skybridge-agent-hub/pull/201001"
      title = "Task bootstrap-trial-201-task-001: Local README Refresh"
      headRefName = "ai/edge-worker/bootstrap-trial-201-task-001-local-readme-refresh"
      token_printed = $false
    })
  }
  try {
    $output = gh pr list --state open --search "bootstrap-trial-201-task-001 in:title,body" --json number,url,title,headRefName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($output | Out-String).Trim())) { return @() }
    return @($output | ConvertFrom-Json | Where-Object {
      [string]$_.title -like "Task bootstrap-trial-201-task-001:*" -or
        [string]$_.headRefName -like "ai/edge-worker/bootstrap-trial-201-task-001-*"
    })
  } catch {
    return @()
  }
}

function ConvertTo-SafeCheckStatus {
  param($Check)
  $status = ([string]$Check.status).ToLowerInvariant()
  $conclusion = ([string]$Check.conclusion).ToLowerInvariant()
  if ($status -eq "completed") {
    switch ($conclusion) {
      "success" { return "success" }
      "failure" { return "failure" }
      "timed_out" { return "failure" }
      "action_required" { return "failure" }
      "cancelled" { return "cancelled" }
      "skipped" { return "skipped" }
      "neutral" { return "skipped" }
      default { return "unknown" }
    }
  }
  if ($status -in @("queued", "in_progress", "waiting", "requested", "pending")) { return "pending" }
  if ($status -eq "cancelled") { return "cancelled" }
  if ($status -eq "failure") { return "failure" }
  if ($status -eq "error") { return "error" }
  return "unknown"
}

function Get-BootstrapTaskPrSnapshot {
  $openPrs = @(Get-OpenBootstrapTaskPrs)
  if ($openPrs.Count -eq 0) {
    return [pscustomobject]@{
      exists = $false
      duplicate_execution_refused = $false
      duplicate_claim_refused = $false
      token_printed = $false
    }
  }
  if ($openPrs.Count -gt 1) { throw "Multiple open bootstrap task PRs detected; refusing to summarize ambiguous state." }
  if ($SimulateExistingOpenTaskPr) {
    return [pscustomobject]@{
      exists = $true
      task_id = "bootstrap-trial-201-task-001"
      pr_number = [int]$openPrs[0].number
      pr_url = [string]$openPrs[0].url
      pr_state = "OPEN"
      task_pr_state = "open"
      base_ref = "main"
      changed_files = @("docs/local-smoke-orientation.md")
      checks_status = "pending"
      checks = @([pscustomobject]@{ name = "fixture"; workflow = "fixture"; status = "pending"; token_printed = $false })
      auto_merge_enabled = $false
      waiting_for_human_review = $true
      duplicate_execution_refused = $true
      duplicate_claim_refused = $true
      raw_ci_logs_persisted = $false
      raw_annotations_persisted = $false
      token_printed = $false
    }
  }
  try {
    $viewJson = gh pr view ([int]$openPrs[0].number) --json number,title,url,state,closed,mergedAt,isDraft,baseRefName,headRefName,files,statusCheckRollup,autoMergeRequest 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($viewJson | Out-String).Trim())) { throw "gh pr view failed." }
    $view = $viewJson | ConvertFrom-Json
    $checks = @($view.statusCheckRollup | ForEach-Object {
      [pscustomobject]@{
        name = [string]$_.name
        workflow = [string]$_.workflowName
        status = ConvertTo-SafeCheckStatus -Check $_
        token_printed = $false
      }
    })
    $checkStatuses = @($checks | ForEach-Object { $_.status })
    $overall = if ($checkStatuses.Count -eq 0) {
      "unknown"
    } elseif ($checkStatuses -contains "failure") {
      "failure"
    } elseif ($checkStatuses -contains "error") {
      "error"
    } elseif ($checkStatuses -contains "cancelled") {
      "cancelled"
    } elseif ($checkStatuses -contains "pending") {
      "pending"
    } elseif (($checkStatuses | Where-Object { $_ -notin @("success", "skipped") }).Count -eq 0) {
      "success"
    } else {
      "unknown"
    }
    [pscustomobject]@{
      exists = $true
      task_id = "bootstrap-trial-201-task-001"
      pr_number = [int]$view.number
      pr_url = [string]$view.url
      pr_state = [string]$view.state
      task_pr_state = ([string]$view.state).ToLowerInvariant()
      base_ref = [string]$view.baseRefName
      changed_files = @($view.files | ForEach-Object { [string]$_.path })
      checks_status = $overall
      checks = @($checks)
      auto_merge_enabled = ($null -ne $view.autoMergeRequest)
      waiting_for_human_review = ($view.state -eq "OPEN" -and $null -eq $view.mergedAt)
      duplicate_execution_refused = $true
      duplicate_claim_refused = $true
      raw_ci_logs_persisted = $false
      raw_annotations_persisted = $false
      token_printed = $false
    }
  } catch {
    [pscustomobject]@{
      exists = $true
      task_id = "bootstrap-trial-201-task-001"
      pr_number = [int]$openPrs[0].number
      pr_url = [string]$openPrs[0].url
      pr_state = "OPEN"
      task_pr_state = "open"
      base_ref = "main"
      changed_files = @()
      checks_status = "unknown"
      checks = @()
      auto_merge_enabled = $false
      waiting_for_human_review = $true
      duplicate_execution_refused = $true
      duplicate_claim_refused = $true
      raw_ci_logs_persisted = $false
      raw_annotations_persisted = $false
      token_printed = $false
    }
  }
}

function Get-StartOneReliabilityReport {
  $snapshot = Get-BootstrapTaskPrSnapshot
  $claimState = Get-OneShotClaimEvidenceState
  $executorEvidencePath = Get-OneShotSanitizedEvidencePath
  $report = [pscustomobject]@{
    ok = $snapshot.exists
    schema = "skybridge.bootstrap_trial_goal202a_start_one_reliability_report.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_id = "bootstrap-trial-201-task-001"
    worker_id = "laptop-zenbookduo"
    final_state = if ($snapshot.exists) { "held_waiting_human_pr_review" } else { "held_no_task_pr" }
    report_state = if ($snapshot.exists) { "held_waiting_human_pr_review" } else { "held_no_task_pr" }
    attention_event = if ($snapshot.exists) { "human_pr_review_required" } else { "task_pr_missing" }
    dashboard = [pscustomobject]@{
      task_id = "bootstrap-trial-201-task-001"
      task_pr_url = $snapshot.pr_url
      task_pr_state = $snapshot.task_pr_state
      checks_status = $snapshot.checks_status
      changed_files = @($snapshot.changed_files)
      no_auto_merge = -not [bool]$snapshot.auto_merge_enabled
      waiting_for_human_review = [bool]$snapshot.waiting_for_human_review
      token_printed = $false
    }
    task_pr = $snapshot
    duplicate_run_prevention = [pscustomobject]@{
      existing_open_task_pr_for_bootstrap_trial = [bool]$snapshot.exists
      start_one_preview_reports_existing_pr = [bool]$snapshot.exists
      start_one_apply_refuses_existing_pr = [bool]$snapshot.exists
      executor_apply_refuses_existing_pr = [bool]$snapshot.exists
      duplicate_execution_refused = [bool]$snapshot.duplicate_execution_refused
      duplicate_claim_refused = [bool]$snapshot.duplicate_claim_refused
      no_second_task = $true
      no_second_task_pr = $true
      token_printed = $false
    }
    evidence = [pscustomobject]@{
      claim_state = $claimState.claim_state
      executor_evidence_exists = Test-Path -LiteralPath $executorEvidencePath -PathType Leaf
      executor_evidence_path = if (Test-Path -LiteralPath $executorEvidencePath -PathType Leaf) { ConvertTo-ShortPath $executorEvidencePath } else { $null }
      trial_report_path = ConvertTo-SafeReportPath (Get-OneShotTrialReportPath)
      prompt_persisted = $false
      transcript_persisted = $false
      stdout_persisted = $false
      stderr_persisted = $false
      raw_ci_logs_persisted = $false
      token_printed = $false
    }
    operator_guidance = @(
      "Review task PR manually.",
      "If acceptable, merge task PR manually.",
      "After merge, run a later goal to attach final evidence and mark bootstrap trial completed.",
      "Do not execute a second task."
    )
    active_tasks = 0
    stale_leases = 0
    no_auto_merge = $true
    token_printed = $false
  }
  if ($Apply) {
    New-Item -ItemType Directory -Path (Get-OneShotStateDir) -Force | Out-Null
    $json = $report | ConvertTo-Json -Depth 100
    if (Test-SecretLookingText $json) { throw "Secret-looking reliability report detected." }
    Set-Content -LiteralPath (Get-OneShotTrialReportPath) -Value $json -Encoding UTF8
  }
  return $report
}

function Get-SafeChangedFiles {
  $files = @(git status --porcelain=v1 | ForEach-Object {
    if ($_ -match "^\s*(?:[AMDRCU?!]{1,2})\s+(.+)$") { $Matches[1].Trim('"').Replace("\", "/") }
  } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
  return @($files)
}

function Test-ChangedFilesAllowed {
  param([string[]]$Files)
  foreach ($file in @($Files)) {
    if (-not (Test-BootstrapAllowedPath -Path $file)) { return $false }
  }
  return $true
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
    command_class = "codex_exec_sanitized_stdin_discard_output"
    host_executable_name = $HostExecutableName
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function Resolve-CodexLauncher {
  param(
    [string]$CandidatePath,
    [string[]]$CodexArguments = @("exec", "--sandbox", "workspace-write", "-")
  )

  $resolvedPath = $null
  if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
    if (-not (Test-Path -LiteralPath $CandidatePath -PathType Leaf)) { throw "Configured Codex launcher was not found." }
    $resolvedPath = (Resolve-Path -LiteralPath $CandidatePath).Path
  } else {
    $command = Get-Command "codex" -ErrorAction SilentlyContinue
    if (-not $command) { throw "Codex CLI was not found on PATH." }
    $resolvedPath = [string]$command.Source
  }

  $extension = [System.IO.Path]::GetExtension($resolvedPath).ToLowerInvariant()
  $fileName = [System.IO.Path]::GetFileName($resolvedPath)

  if ($extension -eq ".exe") {
    return [pscustomobject]@{
      file_path = $resolvedPath
      argument_list = @($CodexArguments)
      metadata = (New-CodexLauncherMetadata -LauncherKind "codex.exe" -HostExecutableName $fileName)
      token_printed = $false
    }
  }

  if ($extension -eq ".cmd" -or $extension -eq ".bat") {
    $cmd = Get-Command "cmd.exe" -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "cmd.exe host for Codex launcher was not found." }
    $commandLine = @(
      (ConvertTo-WindowsCommandLineArgument -Value $resolvedPath)
      @($CodexArguments | ForEach-Object { ConvertTo-WindowsCommandLineArgument -Value ([string]$_) })
    ) -join " "
    return [pscustomobject]@{
      file_path = [string]$cmd.Source
      argument_list = @("/d", "/s", "/c", $commandLine)
      metadata = (New-CodexLauncherMetadata -LauncherKind $extension.TrimStart(".") -HostExecutableName "cmd.exe")
      token_printed = $false
    }
  }

  if ($extension -eq ".ps1") {
    $hostCommand = Get-Command "pwsh" -ErrorAction SilentlyContinue
    if (-not $hostCommand) { $hostCommand = Get-Command "powershell.exe" -ErrorAction SilentlyContinue }
    if (-not $hostCommand) { throw "PowerShell host for Codex launcher was not found." }
    return [pscustomobject]@{
      file_path = [string]$hostCommand.Source
      argument_list = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $resolvedPath) + @($CodexArguments)
      metadata = (New-CodexLauncherMetadata -LauncherKind "ps1" -HostExecutableName ([System.IO.Path]::GetFileName([string]$hostCommand.Source)))
      token_printed = $false
    }
  }

  if ([string]::IsNullOrWhiteSpace($extension)) {
    return [pscustomobject]@{
      file_path = $resolvedPath
      argument_list = @($CodexArguments)
      metadata = (New-CodexLauncherMetadata -LauncherKind "extensionless" -HostExecutableName $fileName)
      token_printed = $false
    }
  }

  throw "Unclassified Codex launcher extension refused."
}

function Invoke-SilentProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [string]$StandardInputText,
    [int]$TimeoutMinutes = 30
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $FilePath
  foreach ($arg in @($ArgumentList)) { [void]$startInfo.ArgumentList.Add($arg) }
  $startInfo.WorkingDirectory = $WorkingDirectory
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardInput = -not [string]::IsNullOrWhiteSpace($StandardInputText)
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo

  [void]$process.Start()
  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if ($startInfo.RedirectStandardInput) {
    $process.StandardInput.Write($StandardInputText)
    $process.StandardInput.Close()
  }
  $timeoutMs = [Math]::Max(1, $TimeoutMinutes) * 60 * 1000
  if (-not $process.WaitForExit($timeoutMs)) {
    try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    $stdoutCharsTimedOut = if ($stdoutTask.IsCompletedSuccessfully) { ([string]$stdoutTask.Result).Length } else { 0 }
    $stderrCharsTimedOut = if ($stderrTask.IsCompletedSuccessfully) { ([string]$stderrTask.Result).Length } else { 0 }
    $process.Dispose()
    return [pscustomobject]@{ ok = $false; exit_code = 124; timed_out = $true; stdout_chars_discarded = $stdoutCharsTimedOut; stderr_chars_discarded = $stderrCharsTimedOut; output_persisted = $false; token_printed = $false }
  }
  $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
  $stderr = [string]$stderrTask.GetAwaiter().GetResult()
  $stdoutChars = $stdout.Length
  $stderrChars = $stderr.Length
  $exitCode = $process.ExitCode
  $process.Dispose()
  [pscustomobject]@{ ok = ($exitCode -eq 0); exit_code = $exitCode; timed_out = $false; stdout_chars_discarded = $stdoutChars; stderr_chars_discarded = $stderrChars; output_persisted = $false; token_printed = $false }
}

function Get-RoutePreview {
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-routing.ps1") -Command worker-route-preview -TaskType local-smoke -Json | ConvertFrom-Json
}

function Get-WorkerServiceReadiness {
  & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-service.ps1") -Command readiness -CampaignId bootstrap-trial-201 -CurrentStepId "bootstrap-trial-201:goal-201-controlled-start-one-bootstrap-trial" -CurrentGoalId goal-201-controlled-start-one-bootstrap-trial -Json | ConvertFrom-Json
}

function Get-Contract {
  $campaignPath = Resolve-RepoPath (Join-Path $CampaignDir "campaign.skybridge.json")
  $goalPath = Resolve-RepoPath (Join-Path $CampaignDir "goal-201-controlled-start-one-bootstrap-trial.md")
  $proposedFullPath = Resolve-RepoPath $ProposedPath
  $campaign = Read-Json $campaignPath
  $goalMeta = Get-MetadataFromMarkdown $goalPath
  $proposedMeta = Get-MetadataFromMarkdown $proposedFullPath
  $errors = New-Object System.Collections.Generic.List[string]

  if ($campaign.campaign_id -ne "bootstrap-trial-201") { $errors.Add("unexpected_campaign_id") | Out-Null }
  if (@($campaign.goals).Count -ne 1) { $errors.Add("trial_campaign_must_have_exactly_one_step") | Out-Null }
  if ($campaign.goals[0].goal_id -ne "goal-201-controlled-start-one-bootstrap-trial") { $errors.Add("unexpected_goal_id") | Out-Null }
  if ($campaign.goals[0].task_type -ne "docs/local-smoke") { $errors.Add("unexpected_task_type") | Out-Null }
  foreach ($type in @("docs", "local-smoke")) {
    if (@($campaign.safety_policy.allowed_task_types) -notcontains $type) { $errors.Add("missing_allowed_task_type:$type") | Out-Null }
  }
  foreach ($field in @("no_start_all", "no_unbounded_worker_loop", "no_auto_merge")) {
    if ($campaign.safety_policy.$field -ne $true) { $errors.Add("missing_policy:$field") | Out-Null }
  }
  if ([int]$campaign.safety_policy.max_steps -ne 1) { $errors.Add("max_steps_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_tasks -ne 1) { $errors.Add("max_tasks_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_prs -ne 1) { $errors.Add("max_prs_not_one") | Out-Null }
  if ([int]$campaign.safety_policy.max_parallel_per_repo -ne 1) { $errors.Add("max_parallel_per_repo_not_one") | Out-Null }
  if ($goalMeta.source_proposed_goal_id -ne $proposedMeta.proposed_goal_id) { $errors.Add("source_proposed_goal_mismatch") | Out-Null }
  if ($proposedMeta.safety_classification -ne "low") { $errors.Add("proposed_goal_not_low_risk") | Out-Null }
  foreach ($type in @("docs", "local-smoke")) {
    if (@($proposedMeta.allowed_task_types) -notcontains $type) { $errors.Add("proposed_goal_missing_allowed_type:$type") | Out-Null }
  }

  [pscustomobject]@{
    ok = ($errors.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_contract.v1"
    campaign_id = $campaign.campaign_id
    campaign_path = ConvertTo-ShortPath $campaignPath
    reviewed_goal_path = ConvertTo-ShortPath $goalPath
    proposed_goal_path = ConvertTo-ShortPath $proposedFullPath
    proposed_goal_id = $proposedMeta.proposed_goal_id
    reviewed_goal_id = $goalMeta.goal_id
    title = $goalMeta.title
    payload = $goalMeta.payload
    risk = $goalMeta.risk
    task_type = $goalMeta.task_type
    allowed_task_types = @($campaign.safety_policy.allowed_task_types)
    review_status = $campaign.review_status
    execution_review_required = [bool]$campaign.goals[0].execution_review_required
    run_budget = [pscustomobject]@{
      max_steps = [int]$campaign.safety_policy.max_steps
      max_tasks = [int]$campaign.safety_policy.max_tasks
      max_prs = [int]$campaign.safety_policy.max_prs
      max_runtime_minutes = [int]$campaign.safety_policy.max_runtime_minutes
      max_parallel_per_repo = [int]$campaign.safety_policy.max_parallel_per_repo
      token_printed = $false
    }
    errors = @($errors)
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    token_printed = $false
  }
}

function Get-GateResult {
  $contract = Get-Contract
  $git = Get-GitState
  $runner = Get-RunnerLockState
  $route = Get-RoutePreview
  $service = Get-WorkerServiceReadiness
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]

  if (-not $contract.ok) { foreach ($item in @($contract.errors)) { $blockers.Add([string]$item) | Out-Null } }
  if (-not $git.clean) { $blockers.Add("worktree_dirty") | Out-Null }
  if (-not $git.dev_queue_200_completion_tag_present) { $blockers.Add("dev_queue_200_completion_tag_missing") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (-not $route.selected_worker) { $blockers.Add("no_single_selected_worker") | Out-Null }
  if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { $blockers.Add("route_preview_not_exactly_one_worker") | Out-Null }
  if ($route.policy.max_parallel_per_repo -ne 1) { $blockers.Add("max_parallel_per_repo_not_enforced") | Out-Null }
  if ($route.repo_parallelism_guard.blocked -eq $true) { $blockers.Add("repo_parallelism_blocked") | Out-Null }
  if ($route.task_created -or $route.task_claimed -or $route.task_executed -or $route.worker_loop_started) { $blockers.Add("route_preview_mutated_execution_state") | Out-Null }

  $claimGate = Get-OneShotClaimGate -Mutate:$false
  $executorGate = Get-OneShotExecutorGate
  $taskPrSnapshot = Get-BootstrapTaskPrSnapshot
  if (-not $claimGate.ok) { foreach ($item in @($claimGate.blockers)) { $blockers.Add([string]$item) | Out-Null } }
  if (-not $executorGate.ok) { foreach ($item in @($executorGate.blockers)) { $blockers.Add([string]$item) | Out-Null } }
  if (-not $executorGate.ok -and -not $taskPrSnapshot.exists) { $warnings.Add("one_shot_execution_held_until_executor_gate_passes") | Out-Null }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_gate.v1"
    command = $Command
    campaign_id = $contract.campaign_id
    selected_step_id = "$($contract.campaign_id):$($contract.reviewed_goal_id)"
    selected_goal_id = $contract.reviewed_goal_id
    task_type = $contract.task_type
    active_tasks = 0
    stale_leases = 0
    runner_lock_status = $runner.runner_lock_status
    repo_lock_status = "clear"
    route_preview = $route
    selected_worker_id = if ($route.selected_worker) { [string]$route.selected_worker.worker_id } else { $null }
    route_reason = if ($route.selected_worker) { "single accepted local worker selected by docs/local-smoke route preview" } else { "no accepted worker" }
    worker_service_readiness = $service.readiness
    run_budget = $contract.run_budget
    operator_reason_recorded = -not [string]::IsNullOrWhiteSpace($Reason)
    attention_state = if ($taskPrSnapshot.exists) { "human_pr_review_required" } else { "one-shot bootstrap trial held: waiting for executor gate" }
    dashboard_state = if ($taskPrSnapshot.exists) { "held_waiting_human_pr_review" } elseif ($executorGate.ok) { "ready_for_one_shot_start_one_apply" } else { "held_no_execution_executor_gate_blocked" }
    task_pr = if ($taskPrSnapshot.exists) { $taskPrSnapshot } else { $null }
    blockers = @($blockers | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    would_create_tasks = if ($blockers.Count -eq 0) { 1 } else { 0 }
    task_created = $false
    task_claimed = $false
    task_executed = $false
    worker_loop_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    start_all_allowed = $false
    second_task_allowed = $false
    external_notification_sent = $false
    token_printed = $false
  }
}

function Get-StartOneApplyResult {
  if ([string]::IsNullOrWhiteSpace($Reason)) { throw "start-one-apply requires -Reason." }
  $gate = Get-GateResult
  if (-not $gate.ok) {
    $existingTaskPr = @($gate.blockers) -contains "existing_open_task_pr_for_bootstrap_trial"
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
      mode = "held"
      campaign_id = $gate.campaign_id
      attempted = $false
      applied = $false
      task_created = $false
      task_id = $null
      task_claimed = $false
      worker_id = $gate.selected_worker_id
      pr_created = $false
      pr_url = $null
      auto_merge_enabled = $false
      final_state = if ($existingTaskPr) { "held_waiting_human_pr_review" } else { "held_no_execution_executor_gate_blocked" }
      hold_reason = if ($existingTaskPr) { "existing open bootstrap task PR requires human review" } else { "one-shot worker executor gate cannot be fully enforced" }
      attention_event = if ($existingTaskPr) { "human_pr_review_required" } else { $null }
      dashboard_state = if ($existingTaskPr) { "held_waiting_human_pr_review" } else { "held_no_execution_executor_gate_blocked" }
      blockers = @($gate.blockers)
      gate = $gate
      no_start_all = $true
      no_second_task = $true
      no_unbounded_worker_loop = $true
      no_resume_apply = $true
      token_printed = $false
    }
  }
  $claimGate = Get-OneShotClaimGate -Mutate:$false
  if (-not $claimGate.ok) {
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
      mode = "held"
      campaign_id = $gate.campaign_id
      attempted = $false
      applied = $false
      task_created = $false
      task_id = $null
      task_claimed = $false
      worker_id = $gate.selected_worker_id
      pr_created = $false
      pr_url = $null
      auto_merge_enabled = $false
      final_state = "held_no_execution_claim_gate_blocked"
      hold_reason = "one-shot claim gate cannot be enforced"
      blockers = @($claimGate.blockers)
      gate = $gate
      no_start_all = $true
      no_second_task = $true
      no_unbounded_worker_loop = $true
      no_resume_apply = $true
      token_printed = $false
    }
  }
  if (-not $Apply) {
    return [pscustomobject]@{
      ok = $true
      schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
      mode = "preview"
      campaign_id = $gate.campaign_id
      attempted = $false
      applied = $false
      task_created = $false
      task_id = $claimGate.task_id
      task_claimed = $false
      worker_id = $gate.selected_worker_id
      pr_created = $false
      pr_url = $null
      auto_merge_enabled = $false
      final_state = "ready_for_one_shot_executor"
      hold_reason = "start-one apply preview only"
      blockers = @()
      gate = $gate
      no_start_all = $true
      no_second_task = $true
      no_unbounded_worker_loop = $true
      no_resume_apply = $true
      token_printed = $false
    }
  }
  $appliedClaim = Get-OneShotClaimGate -Mutate:$true
  [pscustomobject]@{
    ok = $true
    schema = "skybridge.bootstrap_trial_goal201_start_one_apply.v1"
    mode = "apply"
    campaign_id = $gate.campaign_id
    attempted = $true
    applied = $true
    task_created = [bool]$appliedClaim.task_created
    task_id = $appliedClaim.task_id
    task_claimed = [bool]$appliedClaim.task_claimed
    worker_id = $gate.selected_worker_id
    pr_created = $false
    pr_url = $null
    auto_merge_enabled = $false
    final_state = "ready_for_one_shot_executor"
    hold_reason = "start-one apply dry-run surface only; use one-shot executor after final operator gate"
    blockers = @($gate.blockers)
    gate = $gate
    no_start_all = $true
    no_second_task = $true
    no_unbounded_worker_loop = $true
    no_resume_apply = $true
    token_printed = $false
  }
}

function Get-Evidence {
  $gate = Get-GateResult
  [pscustomobject]@{
    ok = $true
    schema = "skybridge.bootstrap_trial_goal201_evidence.v1"
    campaign_id = $gate.campaign_id
    reviewed_goal_path = (Get-Contract).reviewed_goal_path
    proposed_goal_path = (Get-Contract).proposed_goal_path
    task_id = $null
    pr_url = $null
    selected_worker_id = $gate.selected_worker_id
    route_reason = $gate.route_reason
    run_budget = $gate.run_budget
    lease_outcome = "no_lease_created"
    final_state = if ($gate.ok) { "ready_for_one_shot_start_one_apply" } else { "held_no_execution_executor_gate_blocked" }
    active_tasks = 0
    stale_leases = 0
    runner_lock_status = $gate.runner_lock_status
    queue_held = $true
    waiting_for_human_pr_review = $false
    no_start_all = $true
    no_second_task = $true
    no_auto_merge = $true
    raw_transcript_included = $false
    raw_logs_included = $false
    external_notification_sent = $false
    token_printed = $false
  }
}

function Get-OneShotClaimGate {
  param([bool]$Mutate = $false)

  $contract = Get-Contract
  $git = Get-GitState
  $runner = Get-RunnerLockState
  $route = Get-RoutePreview
  $openPrs = @(Get-OpenBootstrapTaskPrs)
  $blockers = New-Object System.Collections.Generic.List[string]
  $warnings = New-Object System.Collections.Generic.List[string]
  $claimEvidencePath = Get-OneShotClaimEvidencePath
  $claimState = Get-OneShotClaimEvidenceState

  if (-not $contract.ok) { foreach ($item in @($contract.errors)) { $blockers.Add([string]$item) | Out-Null } }
  if ($CampaignId -ne "bootstrap-trial-201") { $blockers.Add("wrong_campaign_refused") | Out-Null }
  if ($GoalId -ne "goal-201-controlled-start-one-bootstrap-trial") { $blockers.Add("wrong_goal_refused") | Out-Null }
  if ($TaskType -ne "docs/local-smoke") { $blockers.Add("wrong_task_type_refused") | Out-Null }
  if ($MaxTasks -ne 1) { $blockers.Add("max_tasks_must_be_1") | Out-Null }
  if ($MaxPrs -ne 1) { $blockers.Add("max_prs_must_be_1") | Out-Null }
  if ($MaxRuntimeMinutes -lt 1 -or $MaxRuntimeMinutes -gt 30) { $blockers.Add("max_runtime_minutes_must_be_bounded_1_to_30") | Out-Null }
  foreach ($path in @($AllowedPaths)) {
    if (-not (Test-BootstrapAllowedPath -Path $path)) { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
  }
  if (-not $git.clean) { $blockers.Add("worktree_dirty") | Out-Null }
  if ($runner.runner_lock_status -ne "none") { $blockers.Add("runner_lock_present") | Out-Null }
  if (@($route.decisions | Where-Object { $_.accepted }).Count -ne 1) { $blockers.Add("route_preview_not_exactly_one_worker") | Out-Null }
  if (-not $route.selected_worker -or [string]$route.selected_worker.worker_id -ne "laptop-zenbookduo") { $blockers.Add("selected_worker_not_explicitly_eligible") | Out-Null }
  if ($route.task_created -or $route.task_claimed -or $route.task_executed -or $route.worker_loop_started) { $blockers.Add("route_preview_mutated_execution_state") | Out-Null }
  if ($openPrs.Count -gt 0) { $blockers.Add("existing_open_task_pr_for_bootstrap_trial") | Out-Null }
  if ($claimState.exists) {
    if ($claimState.resumable) {
      $warnings.Add("resumable_owned_claim") | Out-Null
    } else {
      foreach ($item in @($claimState.blockers)) { $blockers.Add([string]$item) | Out-Null }
      if (@($claimState.blockers).Count -eq 0) { $blockers.Add("second_claim_refused") | Out-Null }
    }
  }

  $taskId = "bootstrap-trial-201-task-001"
  $leaseId = "bootstrap-trial-201-lease-001"
  $result = [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_one_shot_claim_gate.v1"
    mode = if ($Mutate) { "apply" } else { "preview" }
    mutates = [bool]$Mutate
    claim_state = if ($claimState.exists -and $claimState.resumable) { "resumable_owned_claim" } elseif ($claimState.exists) { $claimState.claim_state } elseif ($Mutate) { "prepared" } else { "preview" }
    campaign_id = $CampaignId
    goal_id = $GoalId
    task_type = $TaskType
    task_id = if ($blockers.Count -eq 0) { $taskId } else { $null }
    worker_id = if ($route.selected_worker) { [string]$route.selected_worker.worker_id } else { $null }
    route_reason = if ($route.selected_worker) { "single eligible local worker accepted by route preview" } else { "no eligible worker" }
    run_budget = [pscustomobject]@{
      max_tasks = $MaxTasks
      max_prs = $MaxPrs
      max_runtime_minutes = $MaxRuntimeMinutes
      max_parallel_per_repo = 1
      token_printed = $false
    }
    allowed_paths = @($AllowedPaths)
    active_tasks = 0
    stale_leases = 0
    repo_lock_status = "clear"
    runner_lock_status = $runner.runner_lock_status
    open_task_pr_count = $openPrs.Count
    task_created = $false
    task_claimed = $false
    lease_created = $false
    lease_id = $null
    evidence_path = if (($Mutate -or $claimState.exists) -and $blockers.Count -eq 0) { ConvertTo-ShortPath $claimEvidencePath } else { $null }
    executor_evidence_path = $claimState.executor_evidence_path
    blockers = @($blockers | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    start_all_allowed = $false
    start_queue_allowed = $false
    second_task_allowed = $false
    token_printed = $false
  }

  if ($Mutate -and $result.ok -and $claimState.resumable) {
    $evidence = $claimState.evidence
    $evidence | Add-Member -NotePropertyName claim_state -NotePropertyValue "resumable_owned_claim" -Force
    $evidence | Add-Member -NotePropertyName resumed_at -NotePropertyValue (Get-Date).ToUniversalTime().ToString("o") -Force
    $evidence | Add-Member -NotePropertyName executor_evidence_path -NotePropertyValue $null -Force
    $evidence | Add-Member -NotePropertyName pr_url -NotePropertyValue $null -Force
    $evidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $claimEvidencePath -Encoding UTF8
    $result.claim_state = "resumable_owned_claim"
    $result.task_created = $false
    $result.task_claimed = $true
    $result.lease_created = $false
    $result.lease_id = $leaseId
    return $result
  }

  if ($Mutate -and $result.ok) {
    New-Item -ItemType Directory -Path (Get-OneShotStateDir) -Force | Out-Null
    $result.task_created = $true
    $result.task_claimed = $true
    $result.lease_created = $true
    $result.lease_id = $leaseId
    $result.claim_state = "claimed"
    $safeEvidence = [pscustomobject]@{
      schema = "skybridge.bootstrap_trial_goal201_safe_claim_evidence.v1"
      campaign_id = $CampaignId
      goal_id = $GoalId
      task_id = $taskId
      worker_id = $result.worker_id
      lease_id = $leaseId
      allowed_paths = @($AllowedPaths)
      claim_state = "claimed"
      claim_created_at = (Get-Date).ToUniversalTime().ToString("o")
      executor_evidence_path = $null
      pr_url = $null
      prompt_included = $false
      raw_transcript_included = $false
      raw_logs_included = $false
      token_printed = $false
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
    $safeEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $claimEvidencePath -Encoding UTF8
  }
  return $result
}

function Get-OneShotExecutorGate {
  param([bool]$RequireOwnedClaim = $false)

  $claimGate = Get-OneShotClaimGate -Mutate:$false
  $contract = Get-SanitizedExecutorContract
  $blockers = New-Object System.Collections.Generic.List[string]
  $claimState = Get-OneShotClaimEvidenceState
  $ownedClaim = [bool]$claimState.valid_owned
  foreach ($item in @($claimGate.blockers)) {
    $blockers.Add([string]$item) | Out-Null
  }

  if (-not $contract.ok) { foreach ($item in @($contract.blockers)) { $blockers.Add([string]$item) | Out-Null } }
  if ($SimulateRawLogPersistence) { $blockers.Add("sanitized_executor_refused_forced_log_persistence") | Out-Null }
  if ($RequireOwnedClaim -and -not $claimState.resumable) {
    if (-not $claimState.exists) { $blockers.Add("owned_claim_required_for_executor_apply") | Out-Null }
    foreach ($item in @($claimState.blockers)) { $blockers.Add([string]$item) | Out-Null }
  }
  if ($claimState.exists -and -not $claimState.valid_owned) {
    foreach ($item in @($claimState.blockers)) { $blockers.Add([string]$item) | Out-Null }
  }
  if ($claimState.already_executed) {
    if ($claimState.executor_evidence_path) { $blockers.Add("existing_executor_evidence_for_bootstrap_trial") | Out-Null }
    if ($claimState.open_task_pr_count -gt 0) { $blockers.Add("existing_open_task_pr_for_bootstrap_trial") | Out-Null }
  }

  foreach ($path in @($AllowedPaths)) {
    if (-not (Test-BootstrapAllowedPath -Path $path)) { $blockers.Add("path_allowlist_violation:$path") | Out-Null }
  }

  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_one_shot_executor_gate.v1"
    mode = "preview"
    campaign_id = $CampaignId
    goal_id = $GoalId
    task_type = $TaskType
    worker_id = if ($claimGate.worker_id) { $claimGate.worker_id } else { "laptop-zenbookduo" }
    task_id = if ($claimGate.task_id) { $claimGate.task_id } else { "bootstrap-trial-201-task-001" }
    claim_state = if ($claimState.exists) { $claimState.claim_state } else { "absent" }
    claim_evidence_path = if ($claimState.exists) { $claimState.evidence_path } else { $null }
    executor_evidence_path = $claimState.executor_evidence_path
    max_codex_executions = 1
    max_prs = $MaxPrs
    allowed_paths = @($AllowedPaths)
    would_run_codex = ($blockers.Count -eq 0)
    command_class = "codex_exec_sanitized_stdin_discard_output"
    launcher_metadata = $contract.launcher_metadata
    task_claimed = $false
    task_executed = $false
    codex_worker_execution_started = $false
    pr_created = $false
    auto_merge_enabled = $false
    stops_after_pr_or_failure = $true
    prompt_included = $false
    prompt_persisted = $false
    raw_transcript_included = $false
    raw_logs_included = $false
    stdout_persisted = $false
    stderr_persisted = $false
    external_notification_sent = $false
    blockers = @($blockers | Select-Object -Unique)
    token_printed = $false
  }
}

function Get-SanitizedExecutorContract {
  $blockers = New-Object System.Collections.Generic.List[string]
  $launcher = $null
  try {
    $launcher = Resolve-CodexLauncher -CandidatePath $MockCodexPath
  } catch {
    $blockers.Add("codex_launcher_unclassified_or_missing") | Out-Null
  }
  $gh = Get-Command "gh" -ErrorAction SilentlyContinue
  if (-not $gh) { $blockers.Add("github_cli_missing") | Out-Null }
  $launcherMetadata = if ($launcher) { $launcher.metadata } else { $null }
  [pscustomobject]@{
    ok = ($blockers.Count -eq 0)
    schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_contract.v1"
    campaign_id = "bootstrap-trial-201"
    goal_id = "goal-201-controlled-start-one-bootstrap-trial"
    task_type = "docs/local-smoke"
    max_codex_executions = 1
    max_tasks = 1
    max_prs = 1
    prompt_source = "bounded_in_memory_template"
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    command_class = "codex_exec_sanitized_stdin_discard_output"
    launcher_kind = if ($launcherMetadata) { $launcherMetadata.launcher_kind } else { $null }
    launcher_metadata = $launcherMetadata
    saved_metadata = @("task_id", "worker_id", "command_class", "changed_files", "pr_url", "evidence_hashes", "token_printed")
    artifacts_under_ignored_path = ".agent/tmp/bootstrap-trial-201-one-shot/"
    raw_log_persistence_allowed = $false
    arbitrary_shell_exposed = $false
    auto_merge_enabled = $false
    blockers = @($blockers)
    token_printed = $false
  }
}

function New-SanitizedTaskPrompt {
  @"
Execute the controlled SkyBridge bootstrap trial task.

Task id: bootstrap-trial-201-task-001
Campaign: bootstrap-trial-201
Goal: goal-201-controlled-start-one-bootstrap-trial
Task type: docs/local-smoke
Payload: Local README Refresh

Make one small documentation-only improvement to README.md or docs/** that helps local smoke-test orientation for SkyBridge Agent Hub.

Hard limits:
- modify only README.md or docs/**;
- do not touch secrets, .env files, production config, GitHub settings, branch protection, server-root config, or any other repository;
- do not run git commit, git push, gh pr create, start-all, start-queue, resume -Apply, or any worker loop;
- keep the change small and reviewable.
"@
}

function Invoke-CodexLauncherStdinTest {
  if ([string]::IsNullOrWhiteSpace($MockCodexPath)) { throw "codex-launcher-stdin-test requires -MockCodexPath." }
  $stdinText = "skybridge-stdin-fixture-" + [Guid]::NewGuid().ToString("n")
  $launcher = Resolve-CodexLauncher -CandidatePath $MockCodexPath
  $execution = Invoke-SilentProcess -FilePath ([string]$launcher.file_path) -ArgumentList ([string[]]$launcher.argument_list) -WorkingDirectory (Get-RepoRoot) -StandardInputText $stdinText -TimeoutMinutes 1
  $markerPath = $env:SKYBRIDGE_STDIN_MARKER
  $markerText = if (-not [string]::IsNullOrWhiteSpace($markerPath) -and (Test-Path -LiteralPath $markerPath -PathType Leaf)) {
    Get-Content -Raw -LiteralPath $markerPath
  } else {
    $null
  }
  [pscustomobject]@{
    ok = ($execution.ok -and $markerText -eq $stdinText)
    schema = "skybridge.bootstrap_trial_goal201_codex_launcher_stdin_test.v1"
    launcher_metadata = $launcher.metadata
    stdin_preserved = ($markerText -eq $stdinText)
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    token_printed = $false
  }
}

function Invoke-SanitizedOneShotExecutor {
  $gate = Get-OneShotExecutorGate -RequireOwnedClaim:$Apply
  if (-not $gate.ok) {
    $existingTaskPr = @($gate.blockers) -contains "existing_open_task_pr_for_bootstrap_trial"
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_result.v1"
      mode = if ($Apply) { "blocked" } else { "preview" }
      campaign_id = $CampaignId
      task_id = $null
      worker_id = $gate.worker_id
      pr_url = $null
      pr_created = $false
      task_executed = $false
      final_state = if ($existingTaskPr) { "held_waiting_human_pr_review" } else { "held_no_execution_executor_gate_blocked" }
      attention_event = if ($existingTaskPr) { "human_pr_review_required" } else { $null }
      blockers = @($gate.blockers)
      token_printed = $false
    }
  }
  if (-not $Apply) {
    return [pscustomobject]@{
      ok = $true
      schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_result.v1"
      mode = "preview"
      campaign_id = $CampaignId
      task_id = "bootstrap-trial-201-task-001"
      worker_id = $gate.worker_id
      command_class = "codex_exec_sanitized_stdin_discard_output"
      would_run_codex = $true
      pr_created = $false
      task_executed = $false
      token_printed = $false
    }
  }

  $stateDir = Get-OneShotStateDir
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  $claimState = Get-OneShotClaimEvidenceState
  if (-not $claimState.resumable) { throw "Valid owned unexecuted claim is required for executor apply." }
  $taskId = "bootstrap-trial-201-task-001"
  $workerId = "laptop-zenbookduo"
  $branch = "ai/edge-worker/bootstrap-trial-201-task-001-local-readme-refresh"
  $evidencePath = Get-OneShotSanitizedEvidencePath
  if (Test-Path -LiteralPath $evidencePath -PathType Leaf) { throw "Sanitized executor evidence already exists; refusing second execution." }
  if (@(Get-OpenBootstrapTaskPrs).Count -gt 0) { throw "Open bootstrap task PR already exists; refusing second execution." }

  git fetch origin main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed." }
  git switch -C $branch origin/main *> $null
  if ($LASTEXITCODE -ne 0) { throw "git switch task branch failed." }

  $prompt = New-SanitizedTaskPrompt
  $promptHash = Get-Sha256Text -Text $prompt
  $launcher = Resolve-CodexLauncher -CandidatePath $MockCodexPath
  $execution = Invoke-SilentProcess -FilePath ([string]$launcher.file_path) -ArgumentList ([string[]]$launcher.argument_list) -WorkingDirectory (Get-RepoRoot) -StandardInputText $prompt -TimeoutMinutes $MaxRuntimeMinutes
  $changedFiles = @(Get-SafeChangedFiles)
  if (-not $execution.ok) {
    git switch main *> $null
    return [pscustomobject]@{
      ok = $false
      schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_result.v1"
      mode = "controlled_failure"
      campaign_id = $CampaignId
      task_id = $taskId
      worker_id = $workerId
      command_class = "codex_exec_sanitized_stdin_discard_output"
      launcher_metadata = $launcher.metadata
      task_executed = $true
      pr_created = $false
      final_state = "held_no_execution_executor_failed"
      exit_code = $execution.exit_code
      timed_out = $execution.timed_out
      stdout_persisted = $false
      stderr_persisted = $false
      prompt_persisted = $false
      token_printed = $false
    }
  }
  if ($changedFiles.Count -lt 1) { throw "Sanitized executor produced no changed files." }
  if (-not (Test-ChangedFilesAllowed -Files $changedFiles)) { throw "Sanitized executor changed disallowed paths: $($changedFiles -join ', ')" }

  foreach ($file in @($changedFiles)) {
    git add -- $file *> $null
    if ($LASTEXITCODE -ne 0) { throw "git add failed for $file" }
  }
  git commit -m "docs: refresh local smoke orientation" *> $null
  if ($LASTEXITCODE -ne 0) { throw "git commit failed." }
  git push -u origin $branch *> $null
  if ($LASTEXITCODE -ne 0) { throw "git push failed." }

  $bodyPath = Join-Path $stateDir "task-pr-body.md"
  $body = @"
## Summary

Controlled one-shot bootstrap trial for `bootstrap-trial-201`.

## Safety

- Task id: `bootstrap-trial-201-task-001`
- Worker: `laptop-zenbookduo`
- Task type: `docs/local-smoke`
- Changed files: $($changedFiles -join ", ")
- No raw prompt, Codex transcript, stdout or stderr is included.
- No auto-merge requested.
- token_printed=false
"@
  $safeBody = ConvertTo-RedactedText -Text $body
  if (Test-SecretLookingText $safeBody) { throw "Secret-looking PR body detected." }
  Set-Content -LiteralPath $bodyPath -Value $safeBody -Encoding UTF8
  $prOutput = gh pr create --title "Task bootstrap-trial-201-task-001: Local README Refresh" --body-file $bodyPath --base main --head $branch
  if ($LASTEXITCODE -ne 0) { throw "gh pr create failed." }
  $prUrl = (($prOutput | Out-String).Trim() -split "\r?\n" | Select-Object -Last 1)
  $fileSummary = @($changedFiles | ForEach-Object { [pscustomobject]@{ path = $_; sha256 = Get-Sha256Text -Text (Get-Content -Raw -LiteralPath (Resolve-RepoPath $_)); token_printed = $false } })
  $evidence = [pscustomobject]@{
    schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_evidence.v1"
    campaign_id = $CampaignId
    goal_id = $GoalId
    task_id = $taskId
    worker_id = $workerId
    command_class = "codex_exec_sanitized_stdin_discard_output"
    launcher_metadata = $launcher.metadata
    changed_files = @($changedFiles)
    file_evidence = @($fileSummary)
    prompt_sha256 = $promptHash
    prompt_persisted = $false
    transcript_persisted = $false
    stdout_persisted = $false
    stderr_persisted = $false
    output_persisted = $false
    pr_url = $prUrl
    auto_merge_enabled = $false
    final_state = "held_waiting_human_pr_review"
    token_printed = $false
  }
  $evidenceJson = $evidence | ConvertTo-Json -Depth 40
  if (Test-SecretLookingText $evidenceJson) { throw "Secret-looking executor evidence detected." }
  Set-Content -LiteralPath $evidencePath -Value $evidenceJson -Encoding UTF8
  $claimEvidencePath = Get-OneShotClaimEvidencePath
  $claimEvidence = Get-Content -Raw -LiteralPath $claimEvidencePath | ConvertFrom-Json
  $claimEvidence | Add-Member -NotePropertyName claim_state -NotePropertyValue "executed" -Force
  $claimEvidence | Add-Member -NotePropertyName executor_evidence_path -NotePropertyValue (ConvertTo-ShortPath $evidencePath) -Force
  $claimEvidence | Add-Member -NotePropertyName pr_url -NotePropertyValue $prUrl -Force
  $claimEvidence | Add-Member -NotePropertyName token_printed -NotePropertyValue $false -Force
  $claimEvidence | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $claimEvidencePath -Encoding UTF8
  git switch main *> $null
  [pscustomobject]@{
    ok = $true
    schema = "skybridge.bootstrap_trial_goal201_sanitized_executor_result.v1"
    mode = "apply"
    campaign_id = $CampaignId
    task_id = $taskId
    worker_id = $workerId
    command_class = "codex_exec_sanitized_stdin_discard_output"
    launcher_metadata = $launcher.metadata
    changed_files = @($changedFiles)
    pr_url = $prUrl
    pr_created = $true
    task_executed = $true
    evidence_path = ConvertTo-ShortPath $evidencePath
    lease_outcome = "safe_claim_evidence_recorded"
    final_state = "held_waiting_human_pr_review"
    stdout_persisted = $false
    stderr_persisted = $false
    prompt_persisted = $false
    transcript_persisted = $false
    auto_merge_enabled = $false
    token_printed = $false
  }
}

$result = switch ($Command) {
  "contract" { Get-Contract }
  "import-reviewed-goal" { $c = Get-Contract; $c | Add-Member -NotePropertyName imported_or_staged -NotePropertyValue $true -Force; $c }
  "start-one-preview" { Get-GateResult }
  "start-one-gates" { Get-GateResult }
  "start-one-apply" { Get-StartOneApplyResult }
  "one-shot-claim-gate" { Get-OneShotClaimGate -Mutate:$Apply }
  "one-shot-executor-gate" { Get-OneShotExecutorGate }
  "sanitized-executor-contract" { Get-SanitizedExecutorContract }
  "sanitized-executor-gate" { Get-OneShotExecutorGate }
  "sanitized-redaction-test" {
    $sample = "Authorization: Bearer abcdefghijklmnop sk-abcdefghijklmnopqrstuvwxyz ghp_abcdefghijklmnopqrstuvwxyz123456"
    $redacted = ConvertTo-RedactedText -Text $sample
    [pscustomobject]@{
      ok = -not (Test-SecretLookingText $redacted)
      schema = "skybridge.bootstrap_trial_goal201_redaction_test.v1"
      redacted_secret_markers = ($redacted -match "\[REDACTED\]")
      token_printed = $false
    }
  }
  "codex-launcher-stdin-test" { Invoke-CodexLauncherStdinTest }
  "start-one-reliability-report" { Get-StartOneReliabilityReport }
  "run-sanitized-executor" { Invoke-SanitizedOneShotExecutor }
  "worker-route" { Get-RoutePreview }
  "no-start-all" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_no_start_all.v1"; start_all_allowed = $false; blocker = "start_all_forbidden_for_bootstrap_trial_201"; task_created = $false; token_printed = $false } }
  "no-second-task" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_no_second_task.v1"; max_tasks = 1; second_task_allowed = $false; blocker = "max_tasks_1"; task_created = $false; token_printed = $false } }
  "pr-safety" { [pscustomobject]@{ ok = $true; schema = "skybridge.bootstrap_trial_goal201_pr_safety.v1"; target_branch = "main"; allowed_paths = @("README.md", "docs/**"); max_prs = 1; auto_merge_enabled = $false; raw_transcript_allowed = $false; github_settings_mutation_allowed = $false; token_printed = $false } }
  "evidence" { Get-Evidence }
  "clean-worktree" { [pscustomobject]@{ ok = (Get-GitState).clean; schema = "skybridge.bootstrap_trial_goal201_clean_worktree.v1"; git = Get-GitState; token_printed = $false } }
}

$text = $result | ConvertTo-Json -Depth 100 -Compress
if (Test-SecretLookingText $text) { throw "Secret-looking or raw-log output detected." }
if ($Json) { $text } else { $result | Format-List }
