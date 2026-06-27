[CmdletBinding()]
param(
  [switch]$Preview,
  [switch]$ApplyNext,
  [switch]$Fixture,
  [switch]$Live,
  [switch]$Json,
  [switch]$WriteReport,
  [string]$ApiBase = "",
  [string]$TokenFile = "",
  [string]$WorkerId = "",
  [int]$MaxSteps = 1,
  [string]$Confirm = "",
  [string]$OutputDir = ".agent/tmp/multi-goal-loop"
)

$ErrorActionPreference = "Stop"

if (-not $Preview -and -not $ApplyNext) { $Preview = $true }
if ($Live) {
  $Fixture = $false
} elseif (-not $Fixture) {
  $Fixture = $true
}

$controller = Join-Path $PSScriptRoot "skybridge-multi-goal-loop.ps1"
$command = if ($ApplyNext) { "apply-next" } else { "preview-next" }
$args = @(
  "-NoProfile",
  "-ExecutionPolicy",
  "Bypass",
  "-File",
  $controller,
  "-Command",
  $command,
  "-Json",
  "-MaxSteps",
  ([string]$MaxSteps),
  "-OutputDir",
  $OutputDir
)
if ($Fixture) { $args += "-Fixture" }
if ($Live) { $args += "-Live" }
if ($WriteReport) { $args += "-WriteReport" }
if (-not [string]::IsNullOrWhiteSpace($ApiBase)) { $args += @("-ApiBase", $ApiBase) }
if (-not [string]::IsNullOrWhiteSpace($TokenFile)) { $args += @("-TokenFile", $TokenFile) }
if (-not [string]::IsNullOrWhiteSpace($WorkerId)) { $args += @("-WorkerId", $WorkerId) }
if (-not [string]::IsNullOrWhiteSpace($Confirm)) { $args += @("-Confirm", $Confirm) }

$raw = & pwsh @args
if ($LASTEXITCODE -ne 0) { throw "multi-goal loop controller failed." }
$loop = (($raw | Out-String).Trim() | ConvertFrom-Json)

$stepIds = @($loop.steps | Sort-Object order | ForEach-Object { [string]$_.step_id })
$completedSteps = @($loop.steps | Where-Object { $_.completed -eq $true })
$stepsWithEvidence = @($loop.steps | Where-Object { $_.evidence_attached -eq $true })

$checklist = [pscustomobject]@{
  schema = "skybridge.multi_goal_loop_manual_check.v1"
  milestone = "M3: Multi-Step Static Campaign Manual Test"
  mode = $loop.mode
  preview_requested = [bool]$Preview
  apply_next_requested = [bool]$ApplyNext
  max_steps = 1
  one_campaign = ([string]$loop.campaign_id -ne "")
  three_steps = (@($loop.steps).Count -eq 3)
  ordered_step_ids = $stepIds
  one_step_candidate = ([int]$loop.selected_step_count -le 1 -and [int]$loop.selected_task_count -le 1)
  one_task_per_apply_next = ([int]$loop.task_created_count -le 1 -and [int]$loop.task_claimed_count -le 1 -and [int]$loop.execution_completed_count -le 1)
  task_completed_this_apply = ([int]$loop.execution_completed_count -eq 1)
  evidence_attached_this_apply = ([int]$loop.evidence_attached_count -eq 1)
  completed_step_count = @($completedSteps).Count
  evidence_step_count = @($stepsWithEvidence).Count
  campaign_completed_or_held = ([bool]$loop.campaign_completed -or [bool]$loop.campaign_held)
  no_codex_matlab_hermes_mcp_in_fixture = (-not ($loop.codex_run_called -or $loop.matlab_run_called -or $loop.hermes_run_called -or $loop.mcp_run_called))
  no_unbounded_loop = (-not ($loop.worker_loop_started -or $loop.arbitrary_shell_enabled -or $loop.project_control_unpaused))
  token_printed = $false
}

$result = [pscustomobject]@{
  schema = "skybridge.multi_goal_loop_manual_test.v1"
  milestone = "M3: Multi-Step Static Campaign Manual Test"
  checklist = $checklist
  loop = $loop
  token_printed = $false
}

if ($Json) {
  $result | ConvertTo-Json -Depth 60
} else {
  "M3 Manual Test Checklist:"
  "- run fixture preview: $([bool]$Preview)"
  "- run fixture apply-next one step only: $([bool]$ApplyNext)"
  "- verify one campaign: $($checklist.one_campaign)"
  "- verify three ordered steps: $($checklist.three_steps)"
  "- verify one selected task candidate: $($checklist.one_step_candidate)"
  "- verify one task per apply-next: $($checklist.one_task_per_apply_next)"
  "- verify task completed this apply: $($checklist.task_completed_this_apply)"
  "- verify evidence attached this apply: $($checklist.evidence_attached_this_apply)"
  "- verify campaign completed or held: $($checklist.campaign_completed_or_held)"
  "- verify no Codex/MATLAB/Hermes/MCP in fixture: $($checklist.no_codex_matlab_hermes_mcp_in_fixture)"
  "- verify no unbounded loop: $($checklist.no_unbounded_loop)"
  "- token_printed=false"
}
