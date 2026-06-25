[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-codex-native-report-common.ps1"

$context = New-NativeReportSmokeContext -Prefix "smoke-codex-native-validation"

try {
  Write-NativeReportFixtureInputs -Context $context
  New-Item -ItemType Directory -Force -Path $context.output_full | Out-Null
  $reportPath = Join-Path $context.output_full "report.md"
  New-NativeReportMarkdownLines | Set-Content -LiteralPath $reportPath -Encoding UTF8

  $valid = Invoke-NativeReportRunnerValidate -Context $context
  if ($valid.ok -ne $true) { throw "Valid native report should pass validation: $($valid.blockers -join ';')" }
  if ($valid.evidence.validation_status -ne "passed") { throw "Valid native report validation_status should be passed." }
  if ($valid.evidence.native_report_valid -ne $true) { throw "Valid native report should set native_report_valid=true." }
  if ([string]$valid.evidence.final_report_source -ne "codex_native") { throw "Valid native report should set final_report_source=codex_native." }
  if ($valid.evidence.fallback_report_used -ne $false) { throw "Valid native report must not use fallback." }
  if (@($valid.evidence.changed_files).Count -ne 1) { throw "Valid native report should list one changed file." }
  foreach ($relative in @($valid.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Nonexistent changed file listed: $relative" }
  }

  @(
    "# Invalid Native Report",
    "",
    "This is a synthetic MATLAB golden trial runner validation, not a scientific conclusion.",
    "",
    "- expected_combination_count: 2",
    "- completed_count: 2",
    "- failed_count: 0",
    "",
    "stdout: process stream marker should be rejected"
  ) | Set-Content -LiteralPath $reportPath -Encoding UTF8

  $invalid = Invoke-NativeReportRunnerValidate -Context $context
  if ($invalid.ok -ne $false) { throw "Invalid native report should fail validation." }
  if ($invalid.evidence.validation_status -ne "failed") { throw "Invalid native report validation_status should be failed." }
  if ($invalid.evidence.native_report_valid -ne $false) { throw "Invalid native report should set native_report_valid=false." }
  if ([string]$invalid.evidence.native_report_validation_failure_category -ne "native_report_contains_forbidden_raw_or_secret_text") {
    throw "Unexpected native failure category: $($invalid.evidence.native_report_validation_failure_category)"
  }
  if ([string]$invalid.evidence.final_report_source -ne "none") { throw "Invalid native validation should not select a final report source." }
  Assert-False $invalid.evidence.raw_codex_log_included "raw_codex_log_included"
  Assert-False $invalid.evidence.raw_prompt_included "raw_prompt_included"
  Assert-False $invalid.evidence.raw_stdout_included "raw_stdout_included"
  Assert-False $invalid.evidence.raw_stderr_included "raw_stderr_included"
  Assert-TokenPrintedFalse $invalid.evidence

  [pscustomobject]@{
    ok = $true
    smoke = "codex-native-report-validation"
    valid_native_report_passed = $true
    invalid_native_report_rejected = $true
    native_failure_category = [string]$invalid.evidence.native_report_validation_failure_category
    final_report_source = [string]$valid.evidence.final_report_source
    fallback_report_used = $false
    raw_codex_log_included = $false
    raw_prompt_included = $false
    raw_stdout_included = $false
    raw_stderr_included = $false
    matlab_run_called = $false
    pr_created = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-NativeReportSmokeContext -Context $context
}
