[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$nativeScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-codex-analysis-report-native-success.ps1")
$runnerSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-codex-analysis-report-runner.ps1")

foreach ($needle in @(
  "MG339 Codex native report is PowerShell-only for task live-codex-analysis-report-task-339-001",
  "MG339 Codex Native Report status",
  "MG339 native task id",
  "MG339 input manifest exists",
  "MG339 input summary exists",
  "MG339 input metrics exists",
  "MG339 report path",
  "MG339 report exists",
  "MG339 report_size_bytes",
  "MG339 final_report_source",
  "MG339 fallback_report_used",
  "MG339 native_report_valid",
  "MG339 native validation failure category",
  "MG339 validation_status",
  "MG339 evidence summary",
  "MG339 evidence changed_files",
  "MG339 native validation checks",
  "MG339 Codex executable status",
  "MG339 Codex native preview",
  "MG339 Codex native apply unavailable in Desktop",
  "PR creation disabled for MG339",
  "CODEX_NATIVE_REPORT_CREATE_CONFIRMATION_TEXT",
  "CODEX_NATIVE_REPORT_RUN_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop Codex native report panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureCodexNativeReportRunnerPreview",
  "fixtureCodexNativeReportEvidence",
  "fixtureCodexNativeReportPreview",
  "CODEX_NATIVE_REPORT_TASK_ID",
  "live-codex-analysis-report-task-339-001",
  "report_size_bytes",
  "fallback_report_used: false",
  "native_report_valid: true",
  "native_report_validation_failure_category",
  'final_report_source: "codex_native"',
  'codex_failure_category: "none"',
  "raw_codex_log_included: false",
  "raw_prompt_included: false",
  "raw_stdout_included: false",
  "raw_stderr_included: false",
  "matlab_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "pr_created: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client Codex native report fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_NATIVE_REPORT_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_NATIVE_REPORT_TASK_ONLY",
  "live-codex-analysis-report-task-339-001",
  "live-codex-analysis-report-task-337-001",
  "live-codex-analysis-report-task-338-001",
  "mg339-codex-native-report-validation-success",
  "final_report_source",
  "native_report_valid",
  "native_report_validation_failure_category",
  "fallback_report_used",
  "raw_codex_log_included = `$false",
  "raw_prompt_included = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "pr_created = `$false",
  "token_printed = `$false"
)) {
  if ($nativeScript -notmatch [regex]::Escape($needle)) {
    throw "MG339 native orchestrator missing safety text: $needle"
  }
}

foreach ($needle in @(
  "unsupported_runner_arguments",
  "native_report_attempted",
  "native_report_valid",
  "final_report_source",
  "Try-PersistNativeReportFromCapturedText",
  "raw_prompt_included = `$false",
  "raw_stdout_included = `$false",
  "raw_stderr_included = `$false",
  "token_printed = `$false"
)) {
  if ($runnerSource -notmatch [regex]::Escape($needle)) {
    throw "Codex native runner missing hardening text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-codex-native-report"
  target_task_id = "live-codex-analysis-report-task-339-001"
  final_report_source = "codex_native"
  fallback_report_used = $false
  native_report_valid = $true
  desktop_live_apply_enabled = $false
  arbitrary_prompt_box = $false
  arbitrary_shell_enabled = $false
  matlab_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  pr_created = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
