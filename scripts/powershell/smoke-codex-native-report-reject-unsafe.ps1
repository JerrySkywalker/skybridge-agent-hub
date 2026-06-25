[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-codex-native-report-common.ps1"

$context = New-NativeReportSmokeContext -Prefix "smoke-codex-native-reject"
$missingContext = New-NativeReportSmokeContext -Prefix "smoke-codex-native-missing"

try {
  Write-NativeReportFixtureInputs -Context $context

  $missingConfirmRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command apply `
    -TaskId $context.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($context.input_dir)/manifest.json" `
    -InputSummary "$($context.input_dir)/summary.json" `
    -InputMetrics "$($context.input_dir)/metrics.csv" `
    -OutputDir $context.output_dir `
    -Json
  $missingConfirm = (($missingConfirmRaw | Out-String).Trim() | ConvertFrom-Json)
  if ($missingConfirm.ok -ne $false -or ((@($missingConfirm.blockers) -join ";") -notmatch "missing_exact_confirmation")) { throw "Apply without exact confirmation should reject." }
  if ($missingConfirm.codex_invoked -ne $false) { throw "Missing confirmation must not invoke Codex." }

  $unsafeRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command preview `
    -TaskId $context.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($context.input_dir)/manifest.json" `
    -InputSummary "$($context.input_dir)/summary.json" `
    -InputMetrics "$($context.input_dir)/metrics.csv" `
    -OutputDir ".agent/tmp/codex" `
    -Json
  $unsafe = (($unsafeRaw | Out-String).Trim() | ConvertFrom-Json)
  if ($unsafe.ok -ne $false -or ((@($unsafe.blockers) -join ";") -notmatch "output_path_invalid|output_path_suspiciously_truncated")) { throw "Unsafe output path should reject." }

  $missingInputRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command preview `
    -TaskId $missingContext.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($missingContext.input_dir)/manifest.json" `
    -InputSummary "$($missingContext.input_dir)/summary.json" `
    -InputMetrics "$($missingContext.input_dir)/metrics.csv" `
    -OutputDir $missingContext.output_dir `
    -Json
  $missingInput = (($missingInputRaw | Out-String).Trim() | ConvertFrom-Json)
  if ($missingInput.ok -ne $false -or ((@($missingInput.blockers) -join ";") -notmatch "input_manifest_missing|input_summary_missing|input_metrics_missing")) { throw "Missing inputs should reject." }

  $promptAttemptRaw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $NativeReportRunnerScript `
    -Command preview `
    -TaskId $context.task_id `
    -WorkerId "jerry-win-local-01" `
    -InputManifest "$($context.input_dir)/manifest.json" `
    -InputSummary "$($context.input_dir)/summary.json" `
    -InputMetrics "$($context.input_dir)/metrics.csv" `
    -OutputDir $context.output_dir `
    -Prompt "unsafe" `
    -Json
  $promptAttemptText = ($promptAttemptRaw | Out-String).Trim()
  Assert-NoUnsafeText $promptAttemptText
  $promptAttempt = $promptAttemptText | ConvertFrom-Json
  if ($promptAttempt.ok -ne $false -or ((@($promptAttempt.blockers) -join ";") -notmatch "unsupported_runner_arguments")) { throw "Arbitrary -Prompt parameter should be rejected by the fixed runner interface." }
  if ($promptAttempt.codex_invoked -ne $false) { throw "Arbitrary -Prompt rejection must not invoke Codex." }

  Set-FakeCodex -Context $context -Mode "nonzero"
  $nonzero = Invoke-NativeReportRunnerApply -Context $context
  if ($nonzero.ok -ne $false) { throw "Nonzero Codex should fail." }
  if ([string]$nonzero.evidence.codex_failure_category -ne "codex_nonzero_exit") { throw "Expected codex_nonzero_exit." }
  if ($nonzero.evidence.fallback_report_used -ne $false) { throw "Nonzero Codex must not use fallback." }
  if ($nonzero.evidence.validation_status -ne "failed") { throw "Nonzero Codex validation_status should be failed." }

  Remove-Item -LiteralPath $context.output_full -Recurse -Force -ErrorAction SilentlyContinue
  Set-FakeCodex -Context $context -Mode "invalid-file"
  $invalidNative = Invoke-NativeReportRunnerApply -Context $context
  if ($invalidNative.ok -ne $true) { throw "Invalid native report should complete through deterministic fallback." }
  if ($invalidNative.evidence.fallback_report_used -ne $true) { throw "Invalid native report should trigger fallback." }
  if ([string]$invalidNative.evidence.final_report_source -ne "deterministic_fallback") { throw "Fallback final_report_source mismatch." }
  if ([string]$invalidNative.evidence.codex_failure_category -ne "report_validation_failed_after_codex") { throw "Expected report_validation_failed_after_codex." }
  if ([string]$invalidNative.evidence.native_report_validation_failure_category -ne "native_report_missing_completed_count_metric") { throw "Unexpected invalid native category: $($invalidNative.evidence.native_report_validation_failure_category)" }
  if (@($invalidNative.evidence.changed_files).Count -ne 1) { throw "Fallback should list exactly one changed file." }
  foreach ($relative in @($invalidNative.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Nonexistent changed file listed: $relative" }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-native-report-reject-unsafe"
    create_without_confirmation_rejected = $true
    arbitrary_prompt_rejected = $true
    missing_input_files_rejected = $true
    unsafe_output_path_rejected = $true
    nonzero_without_report_failed = $true
    invalid_native_triggers_fallback = $true
    native_report_validation_failure_category = [string]$invalidNative.evidence.native_report_validation_failure_category
    final_report_source = [string]$invalidNative.evidence.final_report_source
    fallback_report_used = [bool]$invalidNative.evidence.fallback_report_used
    changed_files = @($invalidNative.evidence.changed_files)
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-NativeReportSmokeContext -Context $context
  Remove-NativeReportSmokeContext -Context $missingContext
}
