[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-codex-native-report-common.ps1"

$context = New-NativeReportSmokeContext -Prefix "smoke-codex-native-stdout"

try {
  Write-NativeReportFixtureInputs -Context $context
  Set-FakeCodex -Context $context -Mode "valid-stdout"

  $result = Invoke-NativeReportRunnerApply -Context $context
  if ($result.ok -ne $true) { throw "Valid stdout native report should pass after deterministic capture persistence: $($result.blockers -join ';')" }
  if ($result.evidence.report_exists -ne $true) { throw "Captured native report should exist." }
  if ([int64]$result.evidence.report_size_bytes -le 0) { throw "Captured native report should be non-empty." }
  if ($result.evidence.fallback_report_used -ne $false) { throw "Fallback must not be used for valid captured native output." }
  if ($result.evidence.native_report_valid -ne $true) { throw "native_report_valid should be true for captured output." }
  if ([string]$result.evidence.final_report_source -ne "codex_native") { throw "final_report_source should be codex_native." }
  if ([string]$result.evidence.codex_failure_category -ne "none") { throw "codex_failure_category should be none." }
  Assert-False $result.evidence.raw_codex_log_included "raw_codex_log_included"
  Assert-False $result.evidence.raw_prompt_included "raw_prompt_included"
  Assert-False $result.evidence.raw_stdout_included "raw_stdout_included"
  Assert-False $result.evidence.raw_stderr_included "raw_stderr_included"
  Assert-TokenPrintedFalse $result.evidence

  [pscustomobject]@{
    ok = $true
    smoke = "codex-native-report-fallback-not-used-fixture"
    stdout_native_report_persisted = $true
    codex_invoked = [bool]$result.evidence.codex_invoked
    codex_exit_code = [int]$result.evidence.codex_exit_code
    report_exists = [bool]$result.evidence.report_exists
    report_size_bytes = [int64]$result.evidence.report_size_bytes
    final_report_source = [string]$result.evidence.final_report_source
    fallback_report_used = [bool]$result.evidence.fallback_report_used
    native_report_valid = [bool]$result.evidence.native_report_valid
    validation_status = [string]$result.evidence.validation_status
    changed_files = @($result.evidence.changed_files)
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
}
