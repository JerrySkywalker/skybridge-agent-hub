[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$desktopSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "apps\desktop\src\main.tsx")
$clientSource = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "packages\client\src\index.ts")
$runnerScript = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts\powershell\skybridge-worker-template-runner.ps1")

foreach ($needle in @(
  "Bootstrap Alpha Worker Runner Preview",
  "BootstrapAlphaWorkerTemplateRunnerPanel",
  "skybridge.worker_template_runner_preview.v1",
  "skybridge.worker_template_runner_result.v1",
  "Desktop preview-only",
  "MaxTasks=1; claim via PowerShell exact confirmation only",
  "Selected template id",
  "Selected runner id",
  "Rejected reason",
  "Required capabilities",
  "Allowed paths checked",
  "Blocked paths checked",
  "Last evidence summary fixture",
  "Run One unavailable in Desktop",
  "Worker loop unavailable",
  "Codex execution disabled",
  "MATLAB execution disabled",
  "Arbitrary shell disabled",
  "codex_run_called=false; matlab_run_called=false; arbitrary_shell_enabled=false; worker_loop_started=false; token_printed=false",
  "WORKER_TEMPLATE_RUNNER_CONFIRMATION_TEXT"
)) {
  if ($desktopSource -notmatch [regex]::Escape($needle)) {
    throw "Desktop worker template runner panel missing text: $needle"
  }
}

foreach ($needle in @(
  "fixtureWorkerTemplateRunnerPreview",
  "fixtureWorkerTemplateRunnerResult",
  "fixtureTemplateRunnerEvidence",
  "WORKER_TEMPLATE_RUNNER_CONFIRMATION_TEXT",
  "safe-local-smoke.v1",
  "safe-local-smoke-runner.v1",
  "claim_created: true",
  "execution_started: true",
  "execution_completed: true",
  "codex_run_called: false",
  "matlab_run_called: false",
  "arbitrary_shell_enabled: false",
  "worker_loop_started: false",
  "unbounded_run_enabled: false",
  "project_control_unpaused: false",
  "token_printed: false"
)) {
  if ($clientSource -notmatch [regex]::Escape($needle)) {
    throw "Client worker template runner fixture missing text: $needle"
  }
}

foreach ($needle in @(
  "I_UNDERSTAND_RUN_ONE_SAFE_TEMPLATE_TASK_ONLY",
  "MaxTasks -gt 1",
  "missing_exact_confirmation",
  "safe-local-smoke.v1",
  "safe-local-smoke-runner.v1",
  "matlab_template_rejected_mg329",
  "codex_or_docs_runner_deferred_mg329",
  "codex_run_called = `$false",
  "matlab_run_called = `$false",
  "arbitrary_shell_enabled = `$false",
  "worker_loop_started = `$false",
  "unbounded_run_enabled = `$false",
  "project_control_unpaused = `$false",
  "token_printed = `$false"
)) {
  if ($runnerScript -notmatch [regex]::Escape($needle)) {
    throw "Worker template runner script missing safety text: $needle"
  }
}

[pscustomobject]@{
  ok = $true
  smoke = "desktop-worker-template-runner"
  preview_contract = "skybridge.worker_template_runner_preview.v1"
  result_contract = "skybridge.worker_template_runner_result.v1"
  desktop_live_apply_enabled = $false
  claim_created = $false
  execution_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  unbounded_run_enabled = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
