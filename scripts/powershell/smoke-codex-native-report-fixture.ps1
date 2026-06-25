[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-codex-native-report-common.ps1"

$context = New-NativeReportSmokeContext -Prefix "smoke-codex-native-fixture"

try {
  Write-NativeReportFixtureInputs -Context $context
  Set-FakeCodex -Context $context -Mode "valid-file"

  $result = Invoke-NativeReportRunnerApply -Context $context
  if ($result.ok -ne $true) { throw "Valid native-file fake Codex apply should pass: $($result.blockers -join ';')" }
  if ($result.evidence.codex_invoked -ne $true) { throw "Codex should be invoked in fixture apply." }
  if ([int]$result.evidence.codex_exit_code -ne 0) { throw "Codex exit code should be 0." }
  if ([string]$result.evidence.codex_failure_category -ne "none") { throw "codex_failure_category should be none." }
  if ($result.evidence.report_exists -ne $true) { throw "Native report should exist." }
  if ([int64]$result.evidence.report_size_bytes -le 0) { throw "Native report should be non-empty." }
  if ($result.evidence.fallback_report_used -ne $false) { throw "Valid native report must not use fallback." }
  if ($result.evidence.native_report_valid -ne $true) { throw "native_report_valid should be true." }
  if ([string]$result.evidence.final_report_source -ne "codex_native") { throw "final_report_source should be codex_native." }
  if ($result.evidence.validation_status -ne "passed") { throw "validation_status should be passed." }
  if (@($result.evidence.changed_files).Count -ne 1) { throw "Expected exactly one changed file." }
  foreach ($relative in @($result.evidence.changed_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $relative) -PathType Leaf)) { throw "Nonexistent changed file listed: $relative" }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "codex-native-report-fixture"
    codex_invoked = $true
    codex_exit_code = 0
    codex_failure_category = "none"
    report_exists = $true
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
