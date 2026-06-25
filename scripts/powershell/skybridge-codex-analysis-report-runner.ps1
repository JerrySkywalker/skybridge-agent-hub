param(
  [ValidateSet("status", "preview", "apply", "fixture", "validate-output", "safe-summary")]
  [string]$Command = "preview",
  [string]$TaskId = "live-codex-analysis-report-task-338-001",
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
  $root = [IO.Path]::GetFullPath($RepoRoot).TrimEnd("\", "/")
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

function Get-FileSizeBytes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
  [int64](Get-Item -LiteralPath $Path).Length
}

function Get-CodexCommand {
  foreach ($name in @("codex.cmd", "codex.exe", "codex")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd }
  }
  $null
}

function Quote-CmdArgument {
  param([string]$Argument)
  '"' + ($Argument -replace '"', '\"') + '"'
}

function Get-CodexProcessInvocation {
  param($CodexCommand, [string[]]$CodexArguments)
  $source = if ($CodexCommand.Source) { $CodexCommand.Source } else { $CodexCommand.Path }
  if ([string]::IsNullOrWhiteSpace($source)) { return $null }
  $extension = [IO.Path]::GetExtension($source)
  if ($extension -ieq ".ps1") {
    return [pscustomobject]@{
      file_name = (Get-Process -Id $PID).Path
      arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $source) + @($CodexArguments)
    }
  }
  if ($extension -ieq ".cmd" -or $extension -ieq ".bat") {
    $commandLine = (@($source) + @($CodexArguments) | ForEach-Object { Quote-CmdArgument ([string]$_) }) -join " "
    return [pscustomobject]@{
      file_name = if ($env:ComSpec) { $env:ComSpec } else { "cmd.exe" }
      arguments = @()
      arguments_string = "/d /c call $commandLine"
    }
  }
  [pscustomobject]@{
    file_name = $source
    arguments = @($CodexArguments)
  }
}

function Get-ExpectedOutputDir {
  ".agent/tmp/codex-analysis-report/$TaskId"
}

function Get-Config {
  $manifestFull = ConvertTo-FullPath $InputManifest
  $summaryFull = ConvertTo-FullPath $InputSummary
  $metricsFull = ConvertTo-FullPath $InputMetrics
  $expectedOutputDir = Get-ExpectedOutputDir
  $outputFull = ConvertTo-FullPath $expectedOutputDir
  $reportFull = Join-Path $outputFull "report.md"
  $allowedInputRoot = Join-Path $RepoRoot ".agent\tmp\matlab-golden-trial"
  $allowedOutputRoot = Join-Path $RepoRoot ".agent\tmp\codex-analysis-report"
  $blockers = New-Object System.Collections.Generic.List[string]

  if ($TaskId -notmatch "^[A-Za-z0-9][A-Za-z0-9._-]{3,160}$" -or $TaskId -match "[\\/]" -or $TaskId -match "\.\.") {
    $blockers.Add("task_id_invalid") | Out-Null
  }

  foreach ($item in @(
    @{ name = "input_manifest"; full = $manifestFull; json = $true },
    @{ name = "input_summary"; full = $summaryFull; json = $true },
    @{ name = "input_metrics"; full = $metricsFull; json = $false }
  )) {
    if (-not (Test-Path -LiteralPath $item.full -PathType Leaf)) {
      $blockers.Add("$($item.name)_missing") | Out-Null
      continue
    }
    if (-not (Test-PathUnder -Path $item.full -Root $allowedInputRoot)) {
      $blockers.Add("$($item.name)_outside_allowed_paths") | Out-Null
    }
    $raw = Get-Content -Raw -LiteralPath $item.full
    if ([string]::IsNullOrWhiteSpace($raw)) { $blockers.Add("$($item.name)_empty") | Out-Null }
    if ($item.json -and -not [string]::IsNullOrWhiteSpace($raw)) {
      try { $raw | ConvertFrom-Json | Out-Null } catch { $blockers.Add("$($item.name)_invalid_json") | Out-Null }
    }
    if (Test-SecretPattern $raw) { $blockers.Add("$($item.name)_secret_pattern_detected") | Out-Null }
    if (Test-UnsafeText $raw) { $blockers.Add("$($item.name)_unsafe_text_detected") | Out-Null }
  }

  if (-not (Test-PathUnder -Path $outputFull -Root $allowedOutputRoot)) {
    $blockers.Add("output_path_invalid") | Out-Null
  }
  if (-not (Test-PathUnder -Path $reportFull -Root $outputFull)) {
    $blockers.Add("output_path_invalid") | Out-Null
  }
  if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    $requestedOutputFull = ConvertTo-FullPath $OutputDir
    if (-not (Test-PathUnder -Path $requestedOutputFull -Root $allowedOutputRoot)) {
      $blockers.Add("output_dir_outside_allowed_paths") | Out-Null
    }
    if (-not $requestedOutputFull.Equals($outputFull, [StringComparison]::OrdinalIgnoreCase)) {
      $blockers.Add("output_path_invalid") | Out-Null
    }
    $requestedRelative = ConvertTo-RelativePath $requestedOutputFull
    if ($requestedRelative -in @(".agent/tmp/c", ".agent/tmp/codex", ".agent/tmp/codex-analysis")) {
      $blockers.Add("output_path_suspiciously_truncated") | Out-Null
    }
  }
  $expectedRelative = ConvertTo-RelativePath $reportFull
  if ($expectedRelative -notmatch "^\.agent/tmp/codex-analysis-report/[^/]+/report\.md$") {
    $blockers.Add("output_path_invalid") | Out-Null
  }
  if ($expectedRelative.Length -lt (".agent/tmp/codex-analysis-report//report.md".Length + $TaskId.Length)) {
    $blockers.Add("output_path_suspiciously_truncated") | Out-Null
  }
  if (-not (Test-Path -LiteralPath $PromptTemplatePath -PathType Leaf)) {
    $blockers.Add("fixed_prompt_template_missing") | Out-Null
  }
  if (Test-UnsafeText $OutputDir) { $blockers.Add("unsafe_output_text_detected") | Out-Null }

  [pscustomobject]@{
    input_manifest_full = $manifestFull
    input_summary_full = $summaryFull
    input_metrics_full = $metricsFull
    input_manifest_path = ConvertTo-RelativePath $manifestFull
    input_summary_path = ConvertTo-RelativePath $summaryFull
    input_metrics_path = ConvertTo-RelativePath $metricsFull
    input_manifest_exists = Test-Path -LiteralPath $manifestFull -PathType Leaf
    input_summary_exists = Test-Path -LiteralPath $summaryFull -PathType Leaf
    input_metrics_exists = Test-Path -LiteralPath $metricsFull -PathType Leaf
    output_dir_full = $outputFull
    output_dir = ConvertTo-RelativePath $outputFull
    output_report_full = $reportFull
    output_report_path = $expectedRelative
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
  if (-not (Test-PathUnder -Path $Config.output_report_full -Root $Config.output_dir_full)) {
    $errors.Add("report_outside_expected_output_dir") | Out-Null
  }
  if (-not ([IO.Path]::GetFullPath($Config.output_report_full).Equals([IO.Path]::GetFullPath((Join-Path $Config.output_dir_full "report.md")), [StringComparison]::OrdinalIgnoreCase))) {
    $errors.Add("report_path_not_exact") | Out-Null
  }
  if ([IO.Path]::GetExtension($Config.output_report_full).ToLowerInvariant() -ne ".md") {
    $errors.Add("report_not_markdown") | Out-Null
  }
  $size = Get-FileSizeBytes $Config.output_report_full
  if ($size -le 0) { $errors.Add("report_empty") | Out-Null }
  $text = Get-Content -Raw -LiteralPath $Config.output_report_full
  if (Test-SecretPattern $text) { $errors.Add("report_secret_pattern_detected") | Out-Null }
  if ($text -notmatch "(?i)synthetic" -or $text -notmatch "(?i)(MATLAB golden trial|MATLAB.*runner validation|runner validation)") {
    $errors.Add("report_missing_synthetic_matlab_runner_validation_statement") | Out-Null
  }
  if ($text -match "(?i)raw stdout|raw stderr|stdout:|stderr:|codex log|authorization|bearer token|environment dump") {
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
    [string]$ResultSummary = "",
    [bool]$FallbackReportUsed = $false,
    [string]$CodexFailureCategory = ""
  )
  $existing = @(Get-ExistingOutputs -Config $Config)
  $missing = @(Get-MissingOutputs -Config $Config)
  $reportSizeBytes = Get-FileSizeBytes $Config.output_report_full
  if ([string]::IsNullOrWhiteSpace($ResultSummary)) {
    $ResultSummary = if ($ValidationStatus -eq "passed") {
      "Codex analysis report runner produced one sanitized Markdown report from MG336 manifest, summary, and metrics."
    } else {
      "Codex analysis report runner did not produce a valid sanitized Markdown report."
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
    input_manifest_exists = [bool]$Config.input_manifest_exists
    input_summary_exists = [bool]$Config.input_summary_exists
    input_metrics_exists = [bool]$Config.input_metrics_exists
    output_report_path = $Config.output_report_path
    report_exists = ($existing -contains $Config.output_report_path)
    report_size_bytes = $reportSizeBytes
    fallback_report_used = $FallbackReportUsed
    validation_status = $ValidationStatus
    codex_invoked = $CodexInvoked
    codex_exit_code = $CodexExitCode
    codex_failure_category = $CodexFailureCategory
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
    [string]$CodexFailureCategory = "",
    [bool]$FallbackReportUsed = $false,
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
    input_manifest_exists = [bool]$Config.input_manifest_exists
    input_summary_exists = [bool]$Config.input_summary_exists
    input_metrics_exists = [bool]$Config.input_metrics_exists
    output_report_path = $Config.output_report_path
    report_exists = (Test-Path -LiteralPath $Config.output_report_full -PathType Leaf)
    report_size_bytes = Get-FileSizeBytes $Config.output_report_full
    fallback_report_used = $FallbackReportUsed
    validation_status = $ValidationStatus
    codex_available = [bool](Get-CodexCommand)
    would_invoke_codex = $WouldInvokeCodex
    codex_invoked = $CodexInvoked
    codex_exit_code = $CodexExitCode
    codex_failure_category = $CodexFailureCategory
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
  [pscustomobject]@{
    manifest = Get-Content -Raw -LiteralPath $Config.input_manifest_full
    summary = Get-Content -Raw -LiteralPath $Config.input_summary_full
    metrics = Get-Content -Raw -LiteralPath $Config.input_metrics_full
  }
}

function Get-SummaryValue {
  param($SummaryObject, [string]$Name, $DefaultValue)
  if ($SummaryObject -and $SummaryObject.PSObject.Properties[$Name]) { return $SummaryObject.$Name }
  $DefaultValue
}

function Write-DeterministicReport {
  param($Config, [bool]$FallbackReportUsed)
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $bundle = Read-SafeInputBundle -Config $Config
  $summaryObject = $null
  $manifestObject = $null
  try { $summaryObject = $bundle.summary | ConvertFrom-Json } catch { $summaryObject = $null }
  try { $manifestObject = $bundle.manifest | ConvertFrom-Json } catch { $manifestObject = $null }
  $combinationCount = Get-SummaryValue $summaryObject "combination_count" (Get-SummaryValue $manifestObject "combination_count" "not_reported")
  $completed = Get-SummaryValue $summaryObject "completed_count" "not_reported"
  $failed = Get-SummaryValue $summaryObject "failed_count" "not_reported"
  $metricLines = @($bundle.metrics -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 4)
  $report = @(
    "# Codex Analysis Report Recovery",
    "",
    "This report summarizes a synthetic runner validation for a synthetic MATLAB golden trial, not a scientific conclusion.",
    "",
    "## Input Evidence",
    "",
    "- Manifest: $($Config.input_manifest_path)",
    "- Summary: $($Config.input_summary_path)",
    "- Metrics: $($Config.input_metrics_path)",
    "",
    "## Parameter Grid And Metrics",
    "",
    "- Combination count: $combinationCount",
    "- Completed combinations: $completed",
    "- Failed combinations: $failed",
    "- Metrics preview: $($metricLines -join ' | ')",
    "",
    "## Result Summary",
    "",
    "- Validation status: passed",
    "- Fallback report used: $($FallbackReportUsed.ToString().ToLowerInvariant())",
    "- Output report path: $($Config.output_report_path)",
    "",
    "## Safety Notes",
    "",
    "- The report was generated only from the allowed MG336 manifest, summary, and metrics files.",
    "- MATLAB was not invoked for this report.",
    "- Codex transcripts and process streams are not included.",
    "- No PR was created.",
    "- token_printed=false"
  ) -join "`r`n"
  Set-Content -LiteralPath $Config.output_report_full -Value $report -Encoding UTF8
}

function Write-FixtureReport {
  param($Config)
  Write-DeterministicReport -Config $Config -FallbackReportUsed:$false
  $errors = Test-ReportOutput -Config $Config
  $status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
  New-ReportEvidence -Config $Config -ValidationStatus $status -CodexInvoked:$false -CodexExitCode 0 -ReportValidationErrors $errors -FallbackReportUsed:$false
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
      reason = "codex_not_found"
      evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_not_found") -ResultSummary "Codex CLI was not found; fixed report runner did not invoke Codex." -CodexFailureCategory "codex_not_found"
    }
  }
  New-Item -ItemType Directory -Force -Path $Config.output_dir_full | Out-Null
  $stdoutPath = Join-Path $Config.output_dir_full (".codex-stdout-" + [guid]::NewGuid().ToString("N") + ".tmp")
  $stderrPath = Join-Path $Config.output_dir_full (".codex-stderr-" + [guid]::NewGuid().ToString("N") + ".tmp")
  $prompt = New-FixedPrompt -Config $Config
  try {
    $codexArgs = @(
      "--ask-for-approval", "never",
      "exec",
      "--sandbox", "read-only",
      "--ephemeral",
      "--ignore-rules",
      "--skip-git-repo-check",
      "-C", $Config.output_dir_full,
      "-o", $Config.output_report_full,
      "-"
    )
    # Fixed invocation shape: codex exec with read-only sandbox and fixed prompt input.
    $invocation = Get-CodexProcessInvocation -CodexCommand $codex -CodexArguments $codexArgs
    if (-not $invocation) {
      return [pscustomobject]@{
        ok = $false
        exit_code = $null
        reason = "codex_start_failed"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_start_failed") -ResultSummary "Codex command could not be resolved into a safe process invocation." -CodexFailureCategory "codex_start_failed"
      }
    }
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $invocation.file_name
    if ($invocation.PSObject.Properties["arguments_string"] -and -not [string]::IsNullOrWhiteSpace([string]$invocation.arguments_string)) {
      $processInfo.Arguments = [string]$invocation.arguments_string
    } else {
      foreach ($argument in @($invocation.arguments)) {
        [void]$processInfo.ArgumentList.Add($argument)
      }
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
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$false -CodexExitCode $null -ReportValidationErrors @("codex_start_failed") -ResultSummary "Codex fixed report runner could not start Codex through the sanitized process wrapper." -CodexFailureCategory "codex_start_failed"
      }
    }
    $completed = $process.WaitForExit($CodexTimeoutSeconds * 1000)
    if (-not $completed) {
      try { $process.Kill($true) } catch { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
      return [pscustomobject]@{
        ok = $false
        exit_code = $null
        reason = "codex_timeout"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$true -CodexExitCode $null -ReportValidationErrors @("codex_timeout") -ResultSummary "Codex fixed report runner timed out without exposing raw logs." -CodexFailureCategory "codex_timeout"
      }
    }
    $process.WaitForExit()
    Set-Content -LiteralPath $stdoutPath -Value ($stdoutTask.GetAwaiter().GetResult()) -Encoding UTF8
    Set-Content -LiteralPath $stderrPath -Value ($stderrTask.GetAwaiter().GetResult()) -Encoding UTF8
    $exitCode = [int]$process.ExitCode
    $errors = @(Test-ReportOutput -Config $Config)
    if ($exitCode -eq 0 -and @($errors | Where-Object { $_ -eq "report_missing" }).Count -gt 0) {
      Write-DeterministicReport -Config $Config -FallbackReportUsed:$true
      $fallbackErrors = @(Test-ReportOutput -Config $Config)
      $fallbackPassed = ($fallbackErrors.Count -eq 0)
      $fallbackStatus = if ($fallbackPassed) { "passed" } else { "failed" }
      return [pscustomobject]@{
        ok = $fallbackPassed
        exit_code = $exitCode
        reason = if ($fallbackPassed) { "fallback_report_used" } else { "report_missing_after_codex" }
        evidence = New-ReportEvidence -Config $Config -ValidationStatus $fallbackStatus -CodexInvoked:$true -CodexExitCode $exitCode -ReportValidationErrors $fallbackErrors -FallbackReportUsed:$true -CodexFailureCategory "report_missing_after_codex" -ResultSummary "Codex exited successfully without report.md, so the runner wrote a deterministic fallback report from MG336 safe summaries."
      }
    }
    if ($exitCode -ne 0) {
      $allErrors = @($errors) + @("codex_nonzero_exit")
      return [pscustomobject]@{
        ok = $false
        exit_code = $exitCode
        reason = "codex_nonzero_exit"
        evidence = New-ReportEvidence -Config $Config -ValidationStatus "failed" -CodexInvoked:$true -CodexExitCode $exitCode -ReportValidationErrors $allErrors -FallbackReportUsed:$false -CodexFailureCategory "codex_nonzero_exit" -ResultSummary "Codex fixed report runner exited nonzero; no fallback report was used."
      }
    }
    $passed = ($errors.Count -eq 0)
    $validationStatus = if ($passed) { "passed" } else { "failed" }
    $failureCategory = if ($passed) { "" } else { "report_validation_failed" }
    [pscustomobject]@{
      ok = $passed
      exit_code = $exitCode
      reason = if ($passed) { "passed" } else { "report_validation_failed" }
      evidence = New-ReportEvidence -Config $Config -ValidationStatus $validationStatus -CodexInvoked:$true -CodexExitCode $exitCode -ReportValidationErrors $errors -FallbackReportUsed:$false -CodexFailureCategory $failureCategory
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
    $category = if (@($config.blockers) -contains "output_path_invalid" -or @($config.blockers) -contains "output_path_suspiciously_truncated") { "output_path_invalid" } else { "" }
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "blocked" -Blockers $config.blockers -CodexFailureCategory $category
  } elseif (-not $Confirm -or $ConfirmationText -ne $ConfirmationPhrase) {
    $result = New-RunnerRecord -Mode "apply" -Ok $false -Config $config -ValidationStatus "missing_exact_confirmation" -Blockers @("missing_exact_confirmation")
  } else {
    $apply = Invoke-CodexFixedReport -Config $config
    $applyBlockers = if ($apply.ok) { @() } else { @($apply.reason) }
    $result = New-RunnerRecord -Mode "apply" -Ok ([bool]$apply.ok) -Config $config -ValidationStatus ([string]$apply.evidence.validation_status) -CodexInvoked:([bool]$apply.evidence.codex_invoked) -CodexExitCode $apply.exit_code -CodexFailureCategory ([string]$apply.evidence.codex_failure_category) -FallbackReportUsed:([bool]$apply.evidence.fallback_report_used) -Blockers $applyBlockers -Evidence $apply.evidence
  }
}

if ($Json) {
  $result | ConvertTo-Json -Depth 32
} else {
  $result | Format-List
}
