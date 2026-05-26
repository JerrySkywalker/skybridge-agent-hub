$ErrorActionPreference = "Stop"

function New-EdgeWorkerRunDirectory {
  param($Config, $Task)
  $safeWorker = ($Config.worker_id -replace "[^A-Za-z0-9_.-]", "-")
  $safeTask = ($Task.task_id -replace "[^A-Za-z0-9_.-]", "-")
  $runDir = Join-Path $Config.repo_path ".agent/workers/$safeWorker/$safeTask"
  New-Item -ItemType Directory -Force -Path $runDir | Out-Null
  return (Resolve-Path -LiteralPath $runDir).Path
}

function Get-SafeTaskBranchName {
  param($Config, $Task)
  $slug = (($Task.title ?? $Task.task_id) -replace "[^A-Za-z0-9]+", "-").Trim("-").ToLowerInvariant()
  if ($slug.Length -gt 48) { $slug = $slug.Substring(0, 48).Trim("-") }
  if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "task" }
  $prefix = if ($Config.branch_prefix) { [string]$Config.branch_prefix } else { "ai/edge-worker/" }
  return "$prefix$($Task.task_id)-$slug"
}

function Test-ObjectProperty {
  param($InputObject, [Parameter(Mandatory = $true)][string]$Name)
  return $null -ne ($InputObject.PSObject.Properties[$Name])
}

function New-CodexProcessSpec {
  param(
    [Parameter(Mandatory = $true)][string]$ResolvedPath,
    [Parameter(Mandatory = $true)][string]$DisplayCommand,
    [Parameter(Mandatory = $true)][string]$ResolutionSource
  )

  $extension = [System.IO.Path]::GetExtension($ResolvedPath)
  if ($extension -ieq ".ps1") {
    return [pscustomobject]@{
      file_path = "pwsh"
      argument_prefix = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ResolvedPath)
      display_command = $DisplayCommand
      resolved_path = $ResolvedPath
      resolution_source = $ResolutionSource
      powershell_shim = $true
    }
  }

  return [pscustomobject]@{
    file_path = $ResolvedPath
    argument_prefix = @()
    display_command = $DisplayCommand
    resolved_path = $ResolvedPath
    resolution_source = $ResolutionSource
    powershell_shim = $false
  }
}

function Resolve-CodexCommand {
  param($Config)

  $hasConfiguredCommand = (Test-ObjectProperty -InputObject $Config -Name "codex_command") -and -not [string]::IsNullOrWhiteSpace($Config.codex_command)
  if ($hasConfiguredCommand) {
    $candidate = ([string]$Config.codex_command).Trim()
    $isPathLike = [System.IO.Path]::IsPathRooted($candidate) -or $candidate.Contains("\") -or $candidate.Contains("/")
    if ($isPathLike) {
      if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Configured codex_command was not found: $candidate. Set codex_command to an installed Codex CLI path, or remove codex_command to resolve codex from PATH."
      }
      $resolved = (Resolve-Path -LiteralPath $candidate).Path
      return New-CodexProcessSpec -ResolvedPath $resolved -DisplayCommand $candidate -ResolutionSource "config"
    }

    $configuredCommand = Get-Command $candidate -ErrorAction SilentlyContinue
    if (-not $configuredCommand) {
      throw "Configured codex_command '$candidate' was not found on PATH. Set codex_command to an installed Codex CLI path, or remove codex_command to resolve codex from PATH."
    }
    return New-CodexProcessSpec -ResolvedPath $configuredCommand.Source -DisplayCommand $candidate -ResolutionSource "config"
  }

  $pathCommand = Get-Command "codex" -ErrorAction SilentlyContinue
  if (-not $pathCommand) {
    throw "Codex CLI was not found on PATH. Install Codex CLI or set codex_command in the edge worker config to the installed executable, .cmd or .ps1 path."
  }
  return New-CodexProcessSpec -ResolvedPath $pathCommand.Source -DisplayCommand "codex" -ResolutionSource "PATH"
}

function New-CodexTaskPrompt {
  param($Task)
  return @"
Execute SkyBridge task $($Task.task_id) in the local repository.

Title: $($Task.title)
Risk: $($Task.risk)
Source: $($Task.source)
Prompt summary: $($Task.prompt_summary)

Body:
$($Task.body)

Safety boundaries:
- keep the change focused on this task;
- do not touch secrets, .env files, production config, deployment credentials, GitHub settings or server root configuration;
- do not upload raw command output or secrets to SkyBridge;
- for docs-only tasks, modify documentation only;
- do not run git add, git commit, git push or gh pr create; the edge worker owns commit, push and draft PR creation after validation passes.
"@
}

function New-CodexExecArguments {
  param(
    [Parameter(Mandatory = $true)][string]$Sandbox,
    [Parameter(Mandatory = $true)][string]$LastMessagePath
  )

  return @(
    "exec",
    "--sandbox", $Sandbox,
    "--json",
    "--output-last-message", $LastMessagePath,
    "-"
  )
}

function Invoke-LoggedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$ArgumentList,
    [Parameter(Mandatory = $true)][string]$WorkingDirectory,
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$InputPath,
    [int]$TimeoutMinutes = 30
  )

  $errPath = "$LogPath.err"
  $startParams = @{
    FilePath = $FilePath
    ArgumentList = $ArgumentList
    WorkingDirectory = $WorkingDirectory
    NoNewWindow = $true
    PassThru = $true
    RedirectStandardOutput = $LogPath
    RedirectStandardError = $errPath
  }
  if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
    $startParams.RedirectStandardInput = $InputPath
  }
  $process = Start-Process @startParams
  $timeoutMs = [Math]::Max(1, $TimeoutMinutes) * 60 * 1000
  if (-not $process.WaitForExit($timeoutMs)) {
    try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ ok = $false; exit_code = 124; timed_out = $true; log_path = $LogPath; error_log_path = $errPath }
  }
  return [pscustomobject]@{ ok = ($process.ExitCode -eq 0); exit_code = $process.ExitCode; timed_out = $false; log_path = $LogPath; error_log_path = $errPath }
}

function Get-SafeGitChangedFiles {
  param([Parameter(Mandatory = $true)][string]$RepoPath)
  $files = @(git -C $RepoPath status --porcelain=v1 | ForEach-Object {
    if ($_ -match "^\s*(?:[AMDRCU?!]{1,2})\s+(.+)$") { $Matches[1].Trim('"') }
  })
  $files | Where-Object {
    $_ -and
    $_ -notmatch "^(?:\.agent|\.data|node_modules|dist|dist-ts|build|coverage)/" -and
    $_ -notmatch "(^|/)\.env(?:\.|$)" -and
    $_ -notmatch "(?i)(secret|credential|token|cookie|private-key)" -and
    $_ -ne "config/edge-worker.json" -and
    $_ -notmatch "^config/edge-worker\.(?!example|homepc\.example).+\.json$"
  }
}

function Invoke-CodexTask {
  param($Config, $Task)

  $startedAt = (Get-Date).ToUniversalTime().ToString("o")
  $runDir = New-EdgeWorkerRunDirectory -Config $Config -Task $Task
  $branch = Get-SafeTaskBranchName -Config $Config -Task $Task
  $jsonlPath = Join-Path $runDir "codex-exec.jsonl"
  $lastMessagePath = Join-Path $runDir "last-message.md"
  $promptPath = Join-Path $runDir "prompt.md"
  $gitLogPath = Join-Path $runDir "git-branch.log"

  $prompt = New-CodexTaskPrompt -Task $Task
  Set-Content -LiteralPath $promptPath -Value $prompt -Encoding UTF8 -NoNewline

  try {
    $codexCommand = Resolve-CodexCommand -Config $Config
    git -C $Config.repo_path fetch origin main *> $gitLogPath
    if ($LASTEXITCODE -ne 0) { throw "git fetch origin main failed" }
    git -C $Config.repo_path switch -C $branch origin/main *>> $gitLogPath
    if ($LASTEXITCODE -ne 0) { throw "git switch branch failed" }

    $arguments = @($codexCommand.argument_prefix) + @(New-CodexExecArguments -Sandbox ([string]$Config.codex_sandbox) -LastMessagePath $lastMessagePath)
    $codex = Invoke-LoggedProcess -FilePath ([string]$codexCommand.file_path) -ArgumentList $arguments -WorkingDirectory ([string]$Config.repo_path) -LogPath $jsonlPath -InputPath $promptPath -TimeoutMinutes ([int]$Config.max_task_runtime_minutes)
    $changedFiles = @(Get-SafeGitChangedFiles -RepoPath $Config.repo_path)
    $completedAt = (Get-Date).ToUniversalTime().ToString("o")
    return [pscustomobject]@{
      ok = [bool]$codex.ok
      status = if ($codex.ok) { "completed" } elseif ($codex.timed_out) { "blocked" } else { "failed" }
      executor_adapter = "codex-exec"
      branch = $branch
      started_at = $startedAt
      completed_at = $completedAt
      exit_code = $codex.exit_code
      timed_out = $codex.timed_out
      summary = if ($codex.ok) { "Codex exec completed." } else { "Codex exec failed or timed out." }
      run_dir = $runDir
      log_path = $jsonlPath
      error_log_path = $codex.error_log_path
      last_message_path = $lastMessagePath
      prompt_path = $promptPath
      codex_command_resolution = [pscustomobject]@{
        source = $codexCommand.resolution_source
        display_command = $codexCommand.display_command
        resolved_path = $codexCommand.resolved_path
        powershell_shim = [bool]$codexCommand.powershell_shim
      }
      changed_files = $changedFiles
      raw_logs_local_only = $true
    }
  } catch {
    return [pscustomobject]@{
      ok = $false
      status = "failed"
      executor_adapter = "codex-exec"
      branch = $branch
      started_at = $startedAt
      completed_at = (Get-Date).ToUniversalTime().ToString("o")
      exit_code = 1
      summary = "Codex task setup failed."
      error_summary = $_.Exception.Message
      run_dir = $runDir
      log_path = $jsonlPath
      last_message_path = $lastMessagePath
      prompt_path = $promptPath
      changed_files = @()
      raw_logs_local_only = $true
    }
  }
}

function Invoke-TaskValidation {
  param($Config, $Task, $ExecutionResult)

  $commands = @($Config.validation_commands | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_)
  })
  $runDir = if ($ExecutionResult.run_dir) { $ExecutionResult.run_dir } else { New-EdgeWorkerRunDirectory -Config $Config -Task $Task }
  if ($commands.Count -eq 0) {
    return [pscustomobject]@{
      ok = $true
      status = "skipped"
      commands = @()
      summary = "No validation commands configured."
      log_path = $null
    }
  }

  $startedAt = (Get-Date).ToUniversalTime().ToString("o")
  $results = @()
  $index = 0
  foreach ($command in $commands) {
    $index += 1
    $logPath = Join-Path $runDir ("validation-$index.log")
    $result = Invoke-LoggedProcess -FilePath "pwsh" -ArgumentList @("-NoLogo", "-NoProfile", "-Command", [string]$command) -WorkingDirectory ([string]$Config.repo_path) -LogPath $logPath -TimeoutMinutes ([int]$Config.max_task_runtime_minutes)
    $results += [pscustomobject]@{
      command = $command
      ok = $result.ok
      exit_code = $result.exit_code
      timed_out = $result.timed_out
      log_path = $result.log_path
      error_log_path = $result.error_log_path
    }
    if (-not $result.ok) { break }
  }
  $ok = -not ($results | Where-Object { -not $_.ok } | Select-Object -First 1)
  return [pscustomobject]@{
    ok = $ok
    status = if ($ok) { "passed" } else { "failed" }
    commands = $commands
    results = $results
    exit_code = if ($ok) { 0 } else { ($results[-1].exit_code) }
    started_at = $startedAt
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    log_path = if ($results.Count -gt 0) { $results[-1].log_path } else { $null }
    summary = if ($ok) { "Validation passed." } else { "Validation failed." }
    raw_logs_local_only = $true
  }
}

function Invoke-GitPrIntegration {
  param($Config, $Task, $ExecutionResult, $ValidationResult)

  $runDir = $ExecutionResult.run_dir
  $changedFiles = @(Get-SafeGitChangedFiles -RepoPath $Config.repo_path)
  if ($changedFiles.Count -eq 0) {
    return [pscustomobject]@{ ok = $true; status = "skipped"; branch = $ExecutionResult.branch; summary = "No changed files to commit."; changed_files = @() }
  }

  $gitLogPath = Join-Path $runDir "git-pr.log"
  foreach ($file in $changedFiles) {
    git -C $Config.repo_path add -- $file *>> $gitLogPath
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; status = "failed"; branch = $ExecutionResult.branch; summary = "git add failed"; log_path = $gitLogPath } }
  }

  git -C $Config.repo_path commit -m "feat(worker): complete task $($Task.task_id)" *>> $gitLogPath
  if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; status = "failed"; branch = $ExecutionResult.branch; summary = "git commit failed"; log_path = $gitLogPath } }

  git -C $Config.repo_path push -u origin $ExecutionResult.branch *>> $gitLogPath
  if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ ok = $false; status = "failed"; branch = $ExecutionResult.branch; summary = "git push failed"; log_path = $gitLogPath } }

  $bodyPath = Join-Path $runDir "pr-body.md"
  @"
## Summary

$($ExecutionResult.summary)

## Validation

$($ValidationResult.summary)

Task: $($Task.task_id)
Raw Codex and validation logs remain local under $runDir.
"@ | Set-Content -LiteralPath $bodyPath -Encoding UTF8

  $prOutputPath = Join-Path $runDir "gh-pr-create.log"
  gh pr create --draft --title "Task $($Task.task_id): $($Task.title)" --body-file $bodyPath --head $ExecutionResult.branch *> $prOutputPath
  if ($LASTEXITCODE -ne 0) {
    return [pscustomobject]@{ ok = $false; status = "failed"; branch = $ExecutionResult.branch; summary = "gh pr create failed"; log_path = $prOutputPath; changed_files = $changedFiles }
  }
  $prUrl = (Get-Content -Raw -LiteralPath $prOutputPath).Trim()
  $prNumber = $null
  if ($prUrl -match "/pull/(\d+)") { $prNumber = [int]$Matches[1] }
  return [pscustomobject]@{
    ok = $true
    status = "created"
    branch = $ExecutionResult.branch
    pr_number = $prNumber
    pr_url = $prUrl
    summary = "Draft PR created."
    changed_files = $changedFiles
    log_path = $prOutputPath
  }
}

function Invoke-CiGuardianForTask {
  param($Config, $Task, $PRResult)

  if (-not $PRResult.pr_number) {
    return [pscustomobject]@{ ok = $true; status = "skipped"; summary = "No PR number available." }
  }

  $scriptPath = Join-Path $PSScriptRoot "skybridge-ci-guardian.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    return [pscustomobject]@{ ok = $false; status = "failed"; summary = "CI Guardian script missing." }
  }

  $runDir = New-EdgeWorkerRunDirectory -Config $Config -Task $Task
  $logPath = Join-Path $runDir "ci-guardian.log"
  $args = @("-ExecutionPolicy", "Bypass", "-File", $scriptPath, "-PR", [string]$PRResult.pr_number, "-MaxRepairAttempts", "0")
  if ($Config.auto_merge_enabled) {
    $args += @("-EnableAutoMerge", "-PolicyFile", ".\config\auto-merge-policy.example.json")
  }
  $result = Invoke-LoggedProcess -FilePath "pwsh" -ArgumentList $args -WorkingDirectory ([string]$Config.repo_path) -LogPath $logPath -TimeoutMinutes ([int]$Config.max_task_runtime_minutes)
  return [pscustomobject]@{
    ok = $result.ok
    status = if ($result.ok) { "passed" } else { "failed" }
    exit_code = $result.exit_code
    log_path = $logPath
    summary = if ($result.ok) { "CI Guardian completed." } else { "CI Guardian failed or blocked." }
    auto_merge_enabled = [bool]$Config.auto_merge_enabled
    raw_logs_local_only = $true
  }
}
