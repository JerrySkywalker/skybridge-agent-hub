[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$recoveryScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-live-codex-analysis-report-recovery.ps1")

foreach ($needle in @(
  "MG338 Codex artifact recovery is PowerShell-only for task live-codex-analysis-report-task-338-001",
  "MG338 Codex Artifact Recovery status",
  "MG338 recovery task id",
  "MG338 input manifest exists",
  "MG338 input summary exists",
  "MG338 input metrics exists",
  "MG338 output report path",
  "MG338 report exists",
  "MG338 report_size_bytes",
  "MG338 fallback_report_used",
  "MG338 validation_status",
  "MG338 Codex executable status",
  "MG338 evidence summary",
  "MG338 Codex recovery preview",
  "MG338 Codex recovery apply unavailable in Desktop",
  "PR creation disabled for MG338",
  "CODEX_ARTIFACT_RECOVERY_CREATE_CONFIRMATION_TEXT",
  "CODEX_ARTIFACT_RECOVERY_RUN_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop Codex artifact recovery panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureCodexArtifactRecoveryRunnerPreview",
  "fixtureCodexArtifactRecoveryEvidence",
  "fixtureCodexArtifactRecoveryPreview",
  "CODEX_ARTIFACT_RECOVERY_TASK_ID",
  "live-codex-analysis-report-task-338-001",
  "report_size_bytes",
  "fallback_report_used",
  "report_missing_after_codex",
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
    throw "Client Codex artifact recovery fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_CREATE_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY",
  "I_UNDERSTAND_CLAIM_AND_RUN_ONE_LIVE_CODEX_REPORT_RECOVERY_TASK_ONLY",
  "live-codex-analysis-report-task-338-001",
  "live-codex-analysis-report-task-337-001",
  "task_not_created_by_mg338_codex_artifact_recovery",
  "output_report_path",
  "report_size_bytes",
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
  if ($recoveryScript -notmatch [regex]::Escape($needle)) {
    throw "Recovery script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-codex-artifact-recovery"
  target_task_id = "live-codex-analysis-report-task-338-001"
  desktop_live_apply_enabled = $false
  arbitrary_prompt_box = $false
  arbitrary_shell_enabled = $false
  matlab_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  pr_created = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
