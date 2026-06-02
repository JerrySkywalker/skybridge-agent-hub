$ErrorActionPreference = "Stop"
$oldCase = $env:SKYBRIDGE_RUNNER_FIXTURE_CASE
$runnerRoot = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path ".agent\campaign-runners"
try {
  $env:SKYBRIDGE_RUNNER_FIXTURE_CASE = "advanced-past-failed-state"
  New-Item -ItemType Directory -Path $runnerRoot -Force | Out-Null
  @{
    schema = "skybridge.campaign_runner_state.v1"
    runner_id = "runner_old_failed"
    campaign_id = "dev-queue-189-200"
    project_id = "skybridge-agent-hub"
    runner_status = "failed"
    current_step_id = "dev-queue-189-200:super-189-ci-guardian-pr-finalizer-hardening"
    started_at = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
    updated_at = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
    stopped_at = (Get-Date).ToUniversalTime().AddHours(-2).ToString("o")
    max_steps = 12
    max_tasks = 12
    max_runtime_minutes = 30
    steps_attempted = 1
    steps_completed = 0
    tasks_attempted = 1
    tasks_completed = 0
    last_decision = "failed"
    last_error = "old Goal 189 failure"
    audit_log = @()
  } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runnerRoot "dev-queue-189-200.runner.json") -Encoding UTF8
  $json = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-dev-queue-control.ps1" -Command report -Json | ConvertFrom-Json
  if (-not $json.ok) { throw "Expected report ok." }
  $markdown = [string]$json.report.markdown
  if ($markdown -notmatch "super-189-ci-guardian-pr-finalizer-hardening") { throw "Expected Goal 189 in report." }
  if ($markdown -notmatch "super-190-campaign-run-report-evidence-ledger") { throw "Expected Goal 190 in report." }
  if ($markdown -notmatch "historical") { throw "Expected historical runner classification in report." }
} finally {
  if (Test-Path -LiteralPath $runnerRoot) { Remove-Item -LiteralPath $runnerRoot -Recurse -Force }
  if ($null -eq $oldCase) { Remove-Item Env:\SKYBRIDGE_RUNNER_FIXTURE_CASE -ErrorAction SilentlyContinue }
  else { $env:SKYBRIDGE_RUNNER_FIXTURE_CASE = $oldCase }
}
[pscustomobject]@{ ok = $true; scenario = "dev-queue-control-report-current-goal190"; token_printed = $false } | ConvertTo-Json -Compress
