[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$runnerScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-codex-analysis-report-runner.ps1")
$trialScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-codex-analysis-report-trial.ps1")

foreach ($needle in @(
  "MG337 Codex analysis report is PowerShell-only for task live-codex-analysis-report-task-337-001",
  "MG337 Codex Analysis Report status",
  "MG337 target task id",
  "MG337 Codex capability detected",
  "MG337 input manifest exists",
  "MG337 input summary exists",
  "MG337 input metrics exists",
  "MG337 output report path",
  "MG337 report exists",
  "MG337 evidence validation",
  "MG337 raw_codex_log_included",
  "MG337 raw_prompt_included",
  "MG337 Codex report preview",
  "MG337 Codex apply unavailable in Desktop",
  "PR creation disabled for MG337",
  "CODEX_ANALYSIS_REPORT_CREATE_CONFIRMATION_TEXT",
  "CODEX_ANALYSIS_REPORT_RUN_CONFIRMATION_TEXT",
  "CODEX_ANALYSIS_REPORT_RUNNER_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop Codex report panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureCodexAnalysisReportRunnerPreview",
  "fixtureCodexAnalysisReportEvidence",
  "fixtureCodexAnalysisReportPreview",
  "CODEX_ANALYSIS_REPORT_TASK_ID",
  "live-codex-analysis-report-task-337-001",
  "codex-analysis-report.v1",
  "codex-analysis-report-runner.v1",
  "skybridge.codex_analysis_report_evidence.v1",
  "report_exists",
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
    throw "Client Codex report fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_RUN_ONE_FIXED_CODEX_ANALYSIS_REPORT_ONLY",
  "CODEX_ANALYSIS_REPORT_PROMPT_V1.md",
  "codex exec",
  "--sandbox",
  "read-only",
  "--ask-for-approval",
  "never",
  "raw_codex_log_included = `$false",
  "raw_prompt_included = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "pr_created = `$false",
  "token_printed = `$false"
)) {
  if ($runnerScript -notmatch [regex]::Escape($needle)) {
    throw "Codex report runner missing safety text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_ANALYSIS_REPORT_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_ANALYSIS_REPORT_TASK_ONLY",
  "live-codex-analysis-report-task-337-001",
  "live-matlab-golden-task-336-001",
  "task_not_created_by_mg337_codex_report",
  "template_not_supported_mg337_codex_report",
  "expected_task_id",
  "raw_codex_log_included = `$false",
  "raw_prompt_included = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "project_control_unpaused = `$false",
  "pr_created = `$false",
  "token_printed = `$false"
)) {
  if ($trialScript -notmatch [regex]::Escape($needle)) {
    throw "Codex report trial script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-codex-analysis-report"
  target_task_id = "live-codex-analysis-report-task-337-001"
  desktop_live_apply_enabled = $false
  arbitrary_prompt_box = $false
  arbitrary_shell_enabled = $false
  matlab_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  pr_created = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
