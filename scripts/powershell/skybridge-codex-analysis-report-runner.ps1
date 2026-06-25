param(
  [ValidateSet("status", "preview", "apply", "fixture", "validate-output", "safe-summary")]
  [string]$Command = "preview",
  [string]$TaskId = "live-codex-analysis-report-task-337-001",
  [string]$WorkerId = "jerry-win-local-01",
  [string]$InputManifest = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/manifest.json",
  [string]$InputSummary = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/summary.json",
  [string]$InputMetrics = ".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/metrics.csv",
  [string]$OutputDir = "",
  [switch]$Confirm,
  [string]$ConfirmationText = "",
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$TemplateId = "codex-analysis-report.v1"
$RunnerId = "codex-analysis-report-runner.v1"
$EvidenceSchemaId = "skybridge.codex_analysis_report_evidence.v1"
$ConfirmationPhrase = "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$PromptTemplatePath = Join-Path $RepoRoot "docs\product\prompts\CODEX_ANALYSIS_REPORT_PROMPT_V1.md"
$CodexTimeoutSeconds = 300

function ConvertTo-SafeJson {
  param($Value)
  $Value | ConvertTo-Json -Depth 32
}

function ConvertTo-FullPath {
  param([string]$Path)
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  [IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function ConvertTo-RelativePath {
  param([string]$Path)
  $full = [IO.Path]::GetFullPath($Path)
  $root = [IO.Path]::GetFullPath($RepoRoot)
  if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
    return $full.Substring($root.Length).TrimStart("\", "/").Replace("\", "/")
  }
  $full.Replace("\", "/")
}

function Test-PathUnder {
  param([string]$Path, [string]$Root)
  $candidate = [IO.Path]::GetFullPath($Path).TrimEnd("\", "/")
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
  $candidate.Equals($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
    $candidate.StartsWith($rootFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
    $candidate.StartsWith($rootFull + [IO.Path]::AltDirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Test-UnsafeText {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  $positiveText = $Text -replace "(?i)\bNo\s+[^.]*\.", " "
  $positiveText = $positiveText -replace "(?i)\bNot\s+[^.]*\.", " "
  [bool]($positiveText -match "(?i)\b(production|deploy|dns|cloudflare|openresty|authelia|github settings|server-root|secret|cookie|authorization|bearer|raw command|cmd\.exe|powershell -|pwsh -|bash -|matlab -batch|run matlab|arbitrary prompt|create pr|pull request|auto-merge|unbounded|environment dump)\b")
}

function Test-SecretPattern {
  param([string]$Text)
  if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
  [bool]($Text -match "(?i)authorization\s*[:=]\s*bearer|bearer\s+[A-Za-z0-9_.-]{12,}|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|cookie\s*[:=]")
}

function Get-CodexCommand {
  foreach ($name in @("codex.cmd", "codex.exe", "codex")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd }
  }
  $null
}

function Get-CodexProcessInvocation {
  param($CodexCommand)
  $source = if ($CodexCommand.Source) { $CodexCommand.Source } else { $CodexCommand.Path }
  if ([string]::IsNullOrWhiteSpace($source)) { return $null }
  $extension = [IO.Path]::GetExtension($source)
  if ($extension -ieq ".ps1") {
    return [pscustomobject]@{
      file_name = (Get-Process -Id $PID).Path
      prefix_arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $source)
    }
  }
  [pscustomobject]@{
    file_name = $source
    prefix_arguments = @()
  }
}

function Get-Config {
  $outputValue = $OutputDir
  if ([string]::IsNullOrWhiteSpace($outputValue)) {
    $outputValue = ".agent/tmp/codex-analysis-report/$TaskId"
  }
  $manifestFull = ConvertTo-FullPath $InputManifest
  $summaryFull = ConvertTo-FullPath $InputSummary
  $metricsFull = ConvertTo-FullPath $InputMetrics
  $outputFull = ConvertTo-FullPath $outputValue
  $reportFull = Join-Path $outputFull "report.md"
  $blockers = New-Object System.Collections.Generic.List[string]

  foreach ($item in @(
    @{ name = "input_manifest"; full = $manifestFull },
    @{ name = "input_summary"; full = $summaryFull },
    @{ name = "input_metrics"; full = $metricsFull }
  )) {
    if (-not (Test-Path -LiteralPath $item.full -PathType Leaf)) {
      $blockers.Add("$($item.name)_missing") | Out-Null
      continue
    }
    $allowedInputRoot = Join-Path $RepoRoot ".agent\tmp\matlab-golden-trial"
    if (-not (Test-PathUnder -Path $item.full -Root $allowedInputRoot)) {
      $blockers.Add("$($item.name)_outside_allowed_paths") | Out-Null
    }
    $raw = Get-Content -Raw -LiteralPath $item.full
    if (Test-SecretPattern $raw) { $blockers.Add("$($item.name)_secret_pattern_detected") | Out-Null }
    if (Test-UnsafeText $raw) { $blockers.Add("$($item.name)_unsafe_text_detected") | Out-Null }
  }

  $allowedOutputRoot = Join-Path $RepoRoot ".agent\tmp\codex-analysis-report"
  if (-not (Test-PathUnder -Path $outputFull -Root $allowedOutputRoot)) {
    $blockers.Add("output_dir_outside_allowed_paths") | Out-Null
  }
  if (-not (Test-Path -LiteralPath $PromptTemplatePath -PathType Leaf)) {
    $blockers.Add("fixed_prompt_template_missing") | Out-Null
  }
  if (Test-UnsafeText $outputValue) { $blockers.Add("unsafe_output_text_detected") | Out-Null }

  [pscustomobject]@{
    input_manifest_full = $manifestFull
    input_summary_full = $summaryFull
    input_metrics_full = $metricsFull
    input_manifest_path = ConvertTo-RelativePath $manifestFull
    input_summary_path = ConvertTo-RelativePath $summaryFull
    input_metrics_path = ConvertTo-RelativePath $metricsFull
    output_dir_full = $outputFull
    output_dir = ConvertTo-RelativePath $outputFull
    output_report_full = $reportFull
    output_report_path = ConvertTo-RelativePath $reportFull
    blockers = @($blockers.ToArray() | Select-Object -Unique)
  }
}

function Get-ExistingOutputs {
  param($Config)
  if (Test-Path -LiteralPath $Config.output_report_full -PathType Leaf) {
    return @($Config.output_report_path)
  }
  @()
}

function Get-MissingOutputs {
  param($Config)
  if (Test-Path -LiteralPath $Config.output_report_full -PathType Leaf) { return @() }
  @($Config.output_report_path)
}

function Test-ReportOutput {
  param($Config)
  $errors = New-Object System.Collections.Generic.List[string]
  if (-not (Test-Path -LiteralPath $Config.output_report_full -PathType Leaf)) {
    $errors.Add("report_missing") | Out-Null
    return @($errors.ToArray())
  }
  if ([IO.Path]::GetExtension($Config.output_report_full).ToLowerInvariant() -ne ".md") {
    $errors.Add("report_not_markdown") | Out-Null
  }
  $text = Get-Content -Raw -LiteralPath $Config.output_report_full
  if (Test-SecretPattern $text) { $errors.Add("report_secret_pattern_detected") | Out-Null }
  if ($text -notmatch "(?i)synthetic runner validation") {
    $errors.Add("report_missing_synthetic_runner_validation_statement") | Out-Null
  }
  if ($text -match "(?i)raw stdout|raw stderr|codex log|authorization|bearer token|environment dump") {
    $errors.Add("report_contains_forbidden_raw_or_secret_text") | Out-Null
  }
  @($errors.ToArray())
}

function New-ReportEvidence {
  param(
    $Config,
    [string]$ValidationStatus,
    [bool]$CodexInvoked,
    [Nullable[int]]$CodexExitCode,
    [string[]]$ReportValidationErrors = @(),
    [string]$ResultSummary = ""
  )
  $existing = @(Get-ExistingOutputs -Config $Config)
  $missing = @(Get-MissingOutputs -Config $Config)
  if ([string]::IsNullOrWhiteSpace($ResultSummary)) {
    $ResultSummary = if ($ValidationStatus -eq "passed") {
      "Fixed Codex analysis report runner produced one sanitized Markdown report from MG336 manifest, summary, and metrics."
    } else {
      "Fixed Codex analysis report runner did not produce a valid sanitized Markdown report."
    }
  }
  [pscustomobject]@{
    schema = $EvidenceSchemaId
    ok = ($ValidationStatus -eq "passed")
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    input_manifest_path = $Config.input_manifest_path
    input_summary_path = $Config.input_summary_path
    input_metrics_path = $Config.input_metrics_path
    output_report_path = $Config.output_report_path
    report_exists = ($existing -contains $Config.output_report_path)
    validation_status = $ValidationStatus
    codex_invoked = $CodexInvoked
    codex_exit_code = $CodexExitCode
    allowed_paths_checked = $true
    blocked_paths_checked = $true
    changed_files = @($existing)
    existing_outputs = @($existing)
    expected_outputs_missing = @($missing)
    report_validation_errors = @($ReportValidationErrors)
    result_summary = $ResultSummary
    project_control_unpaused = $false
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    pr_created = $false
    token_printed = $false
  }
}

function New-RunnerRecord {
  param(
    [string]$Mode,
    [bool]$Ok,
    $Config,
    [string]$ValidationStatus = "not_run",
    [bool]$CodexInvoked = $false,
    [Nullable[int]]$CodexExitCode = $null,
    [string[]]$Blockers = @(),
    [string[]]$Warnings = @(),
    [bool]$WouldInvokeCodex = $false,
    $Evidence = $null
  )
  $record = [pscustomobject]@{
    schema = "skybridge.codex_analysis_report_runner.v1"
    ok = $Ok
    mode = $Mode
    task_id = $TaskId
    worker_id = $WorkerId
    template_id = $TemplateId
    runner_id = $RunnerId
    input_manifest_path = $Config.input_manifest_path
    input_summary_path = $Config.input_summary_path
    input_metrics_path = $Config.input_metrics_path
    output_report_path = $Config.output_report_path
    report_exists = (Test-Path -LiteralPath $Config.output_report_full -PathType Leaf)
    validation_status = $ValidationStatus
    codex_available = [bool](Get-CodexCommand)
    would_invoke_codex = $WouldInvokeCodex
    codex_invoked = $CodexInvoked
    codex_exit_code = $CodexExitCode
    blockers = @($Blockers | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    warnings = @($Warnings | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    pr_created = $false
    token_printed = $false
  }
  if ($Evidence) { $record | Add-Member -NotePropertyName evidence -NotePropertyValue $Evidence }
  $record
}

function Read-SafeInputBundle {
  param($Config)
  $manifest = Get-Content -Raw -LiteralPath $Config.input_manifest_full
  $summary = Get-Content -Raw -LiteralPath $Config.input_summary_full
  $metrics = Get-Content -Raw -LiteralPath $Config.input_metrics_full
  [pscustomobject]@{
    manifest = $manifest
    summary = $summary
    metrics = $metrics
  }
}

function Write-FixtureReport {
  param($Config)
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $bundle = Read-SafeInputBundle -Config $Config
  $summaryObject = $null
  try { $summaryObject = $bundle.summary | ConvertFrom-Json } catch { $summaryObject = $null }
  $completed = if ($summaryObject -and $summaryObject.PSObject.Properties["completed_count"]) { [int]$summaryObject.completed_count } else { 2 }
  $failed = if ($summaryObject -and $summaryObject.PSObject.Properties["failed_count"]) { [int]$summaryObject.failed_count } else { 0 }
  $report = @(
    "# MG337 Codex Analysis Report",
    "",
    "This report summarizes a synthetic runner validation, not a scientific conclusion.",
    "",
    "## Inputs",
    "",
    "- Manifest: $($Config.input_manifest_path)",
    "- Summary: $($Config.input_summary_path)",
    "- Metrics: $($Config.input_metrics_path)",
    "",
    "## Result",
    "",
    "- Completed combinations: $completed",
    "- Failed combinations: $failed",
    "- Validation status: passed",
    "",
    "## Safety",
    "",
    "- MATLAB console streams were excluded.",
    "- Codex execution transcripts were excluded.",
    "- No PR was created.",
    "- token_printed=false"
  ) -join "`r`n"
  Set-Content -LiteralPath $Config.output_report_full -Value $report -Encoding UTF8
  $errors = Test-ReportOutput -Config $Config
  $status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
  New-ReportEvidence -Config $Config -ValidationStatus $status -CodexInvoked:$false -CodexExitCode 0 -ReportValidationErrors $errors
}

function New-FixedPrompt {
  param($Config)
  $template = Get-Content -Raw -LiteralPath $PromptTemplatePath
  $bundle = Read-SafeInputBundle -Config $Config
  @"
$template

SAFE INPUT FILE CONTENTS FOLLOW. They were loaded only from the configured MG336 manifest, summary, and metrics files.

Input manifest path: $($Config.input_manifest_path)
```json
$($bundle.manifest)
```

Input summary path: $($Config.input_summary_path)
```json
$($bundle.summary)
```

Input metrics path: $($Config.input_metrics_path)
```csv
$($bundle.metrics)
```

Return the Markdown report only.
"@
}

function Invoke-CodexFixedReport {
  param($Config)
  $codex = Get-CodexCommand
  if (-not $codex) {
    return [pscustomobject]@{
      ok = $false
      exit_code = $null
      reason = "codex_not_available"
      evidence = New-ReportEvidence -Config $Config -ValidationStatus "codex_not_available" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_not_available") -ResultSummary "Codex CLI was not available; fixed report runner did not invoke Codex."
    }
  }
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $stdoutPath = [IO.Path]::GetTempFileName()
  $stderrPath = [IO.Path]::GetTempFileName()
  $prompt = New-FixedPrompt -Config $Config
  try {
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $invocation = Get-CodexProcessInvocation -CodexCommand $codex
    if (-not $invocation) {
      return [pscustomobject]@{
        ok = $false
        exit_code = $null
        reason = "codex_command_resolution_failed"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_command_resolution_failed") -ResultSummary "Codex command could not be resolved into a safe process invocation."
      }
    }
    $processInfo.FileName = $invocation.file_name
    foreach ($argument in @($invocation.prefix_arguments)) {
      [void]$processInfo.ArgumentList.Add($argument)
    }
    # Fixed invocation shape: codex exec with a read-only sandbox and fixed prompt input.
    foreach ($argument in @(
      "exec",
      "--sandbox", "read-only",
      "--ask-for-approval", "never",
      "--ephemeral",
      "--ignore-rules",
      "--skip-git-repo-check",
      "-C", $Config.output_dir_full,
      "-o", $Config.output_report_full,
      "-"
    )) {
      [void]$processInfo.ArgumentList.Add($argument)
    }
    $processInfo.WorkingDirectory = $Config.output_dir_full
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    try {
      [void]$process.Start()
      $process.StandardInput.Write($prompt)
      $process.StandardInput.Close()
      $stdoutTask = $process.StandardOutput.ReadToEndAsync()
      $stderrTask = $process.StandardError.ReadToEndAsync()
    } catch {
      try {
        if ($process -and -not $process.HasExited) { $process.Kill($true) }
      } catch {
        try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
      }
      return [pscustomobject]@{
        ok = $false
        exit_code = $null
        reason = "codex_start_failed"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_start_failed") -ResultSummary "Codex fixed report runner could not start Codex through the sanitized process wrapper."
      }
    }
    $completed = $process.WaitForExit($CodexTimeoutSeconds * 1000)
    if (-not $completed) {
      try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
      return [pscustomobject]@{
        ok = $false
        exit_code = $null
        reason = "codex_runner_timeout"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$true -CodexExitCode $null -ReportValidationErrors @("codex_runner_timeout") -ResultSummary "Codex fixed report runner timed out without exposing raw logs."
      }
    }
    $process.WaitForExit()
    Set-Content -LiteralPath $stdoutPath -Value ($stdoutTask.GetAwaiter().GetResult()) -Encoding UTF8
    Set-Content -LiteralPath $stderrPath -Value ($stderrTask.GetAwaiter().GetResult()) -Encoding UTF8
    $errors = Test-ReportOutput -Config $Config
    $passed = ([int]$process.ExitCode -eq 0 -and @($errors).Count -eq 0)
    $status = if ($passed) { "passed" } else { "failed" }
    $allErrors = @($errors)
    if ([int]$process.ExitCode -ne 0) { $allErrors += "codex_exit_nonzero" }
    [pscustomobject]@{
      ok = $passed
      exit_code = [int]$process.ExitCode
      reason = if ($passed) { "passed" } else { ($allErrors -join ";") }
      evidence = New-ReportEvidence -Config $Config -ValidationStatus $status -CodexInvoked:$true -CodexExitCode ([int]$process.ExitCode) -ReportValidationErrors $allErrors
    }
  } finally {
    Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
  }
}

$config = Get-Config

if ($Command -eq "status") {
  $result = New-RunnerRecord -Mode "status" -Ok $true -Config $config -ValidationStatus "status_only" -Warnings @("apply_requires_exact_confirmation")
} elseif ($Command -eq "safe-summary") {
  $result = New-RunnerRecord -Mode "safe-summary" -Ok $true -Config $config -ValidationStatus "safe_summary_only" -Warnings @("fixed_prompt_template_only_no_raw_logs")
} elseif ($Command -eq "preview") {
  $blockers = @($config.blockers)
  $previewStatus = if ($blockers.Count -eq 0) { "preview_only" } else { "blocked" }
  $result = New-RunnerRecord -Mode "preview" -Ok ($blockers.Count -eq 0) -Config $config -ValidationStatus $previewStatus -Blockers $blockers -WouldInvokeCodex ($blockers.Count -eq 0)
} elseif ($Command -eq "fixture") {
  if ($config.blockers.Count -gt 0) {
    $result = New-RunnerRecord -Mode "fixture" -Ok $false -Config $config -ValidationStatus "blocked" -Blockers $config.blockers
  } else {
    $evidence = Write-FixtureReport -Config $config
    $result = New-RunnerRecord -Mode "fixture" -Ok ([bool]$evidence.ok) -Config $config -ValidationStatus ([string]$evidence.validation_status) -Warnings @("fixture_mode_no_codex_invocation") -Evidence $evidence
  }
} elseif ($Command -eq "validate-output") {
  $errors = Test-ReportOutput -Config $config
  $status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
  $evidence = New-ReportEvidence -Config $config -ValidationStatus $status -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors $errors
  $result = New-RunnerRecord -Mode "validate-output" -Ok ($errors.Count -eq 0) -Config $config -ValidationStatus $status -Blockers $errors -Evidence $evidence
} else {
  if ($config.blockers.Count -gt 0) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "blocked" -Blockers $config.blockers
  } elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "missing_exact_confirmation" -Blockers @("missing_exact_confirmation")
  } else {
    $apply = Invoke-CodexFixedReport -Config $config
    $applyBlockers = if ($apply.ok) { @() } else { @($apply.reason) }
    $result = New-RunnerRecord -Mode "apply" -Ok ([bool]$apply.ok) -Config $config -ValidationStatus ([string]$apply.evidence.validation_status) -CodexInvoked:([bool]$apply.evidence.codex_invoked) -CodexExitCode $apply.exit_code -Blockers $applyBlockers -Evidence $apply.evidence
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 32
} else {
  $result | Format-List
}
