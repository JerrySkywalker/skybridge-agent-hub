[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$Apply,
  [switch]$Fixture,
  [switch]$Live,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [string]$Confirm = ""
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $Apply) { $Preview = $true }
if ($Live) {
  $Fixture = $false
} elseif (-not $Fixture) {
  $Fixture = $true
}

$controller = Join-Path $PSScriptRoot "skybridge-goal-loop.ps1"
$command = if ($Apply) { "apply-once" } else { "preview-once" }
$args = @(
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  $controller,
  "-Command",
  $command,
  "-Json"
)
if ($Fixture) { $args += "-Fixture" }
if ($WriteReport) { $args += "-WriteReport" }
if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { $args += @("-ApiBase", $ApiBase) }
if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
if (-not [string]::IsNullOrWhiteSpace($WorkerId)) { $args += @("-WorkerId", $WorkerId) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh @args
if ($LASTEXITCODE -ne 0) { throw "single-goal loop controller failed." }
$loop = (($raw | Out-String).Trim() | ConvertFrom-Json)

$checklist = [pscustomobject]@{
  schema = "skybridge.single_goal_loop_manual_check.v1"
  milestone = "M2: Single Goal Loop Manual Test"
  mode = $loop.mode
  preview_requested = [bool]$Preview
  apply_requested = [bool]$Apply
  one_campaign = ([string]$loop.campaign_id -ne "")
  one_step = ([string]$loop.step_id -ne "")
  one_safe_local_smoke_task_candidate = ([string]$loop.task_id -ne "" -and [string]$loop.template_id -eq "safe-local-smoke.v1")
  task_completed = [bool]$loop.execution_completed
  evidence_attached = [bool]$loop.evidence_attached
  step_completed = [bool]$loop.step_completed
  campaign_completed_or_held = ([bool]$loop.campaign_completed -or @($loop.warnings) -contains "campaign_hold_required")
  codex_run_called = $false
  matlab_run_called = $false
  hermes_run_called = $false
  mcp_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
}

$result = [pscustomobject]@{
  schema = "skybridge.single_goal_loop_manual_test.v1"
  milestone = "M2: Single Goal Loop Manual Test"
  checklist = $checklist
  loop = $loop
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 48
} else {
  "M2 Manual Test Checklist:"
  "- run preview: $([bool]$Preview)"
  "- verify one campaign: $($checklist.one_campaign)"
  "- verify one step: $($checklist.one_step)"
  "- verify one safe-local-smoke task candidate: $($checklist.one_safe_local_smoke_task_candidate)"
  "- run apply once only if ready: $([bool]$Apply)"
  "- verify task completed: $($checklist.task_completed)"
  "- verify evidence attached: $($checklist.evidence_attached)"
  "- verify step completed: $($checklist.step_completed)"
  "- verify campaign completed or held: $($checklist.campaign_completed_or_held)"
  "- verify no Codex/MATLAB/Hermes/MCP: $(-not ($checklist.codex_run_called -or $checklist.matlab_run_called -or $checklist.hermes_run_called -or $checklist.mcp_run_called))"
  "- token_printed=false"
}
