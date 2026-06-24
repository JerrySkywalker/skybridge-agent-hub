[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$runnerScript = Join-Path $PSScriptRoot "skybridge-matlab-parameter-sweep-runner.ps1"
$successScript = Join-Path $PSScriptRoot "skybridge-live-matlab-golden-success.ps1"
$LiveTaskId = "live-matlab-golden-task-336-001"
$BlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")

function Invoke-Runner {
  param([string[]]$ScriptArgs)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $runnerScript @ScriptArgs -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Invoke-SuccessPreview {
  param([string]$TaskId = $LiveTaskId)
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $successScript `
    -Command preview-run `
    -ApiBase $script:WorkerTemplateRunnerApiBase `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId $TaskId `
    -TemplateId "matlab-parameter-sweep.v1" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

function Initialize-FixtureServer {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG336 MATLAB Success Reject Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "matlab")
    labels = @("mg336-fixture", "reject-unsafe")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{
    status_note = "mg336 reject fixture ready"
    load = 0
  } | Out-Null
}

function New-SuccessTaskBody {
  param(
    [string]$TaskId = $LiveTaskId,
    [string[]]$AllowedPaths = @(".agent/tmp/matlab-golden-trial/**", "results/skybridge/matlab-golden-trial/**"),
    [string]$Body = "Run the fixed MG336 synthetic MATLAB success trial only.",
    [bool]$SuccessMetadata = $true,
    [string]$TemplateId = "matlab-parameter-sweep.v1",
    [string]$RunnerId = "matlab-parameter-sweep-runner.v1",
    [string[]]$RequiredCapabilities = @("windows", "powershell", "matlab")
  )
  $metadata = @{
    adapter = if ($SuccessMetadata) { "mg336-matlab-golden-success" } else { "mg336-matlab-rejection-fixture" }
    decision = "continue"
    reason = if ($SuccessMetadata) { "mg336_one_live_matlab_success_trial" } else { "mg336_rejection_fixture" }
    task_type = "matlab-parameter-sweep"
    template_id = $TemplateId
    runner_id = $RunnerId
    evidence_schema = @("skybridge.matlab_sweep_evidence.v1")
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @("Reject unsafe or unsupported MG336 MATLAB success trial.")
    expected_outputs = @(".agent/tmp/matlab-golden-trial/live-matlab-golden-task-336-001/**")
    stop_criteria_status = @("reject_without_claim")
    source_run_id = if ($SuccessMetadata) { "mega-goal-336-matlab-golden-recovery-success" } else { "mega-goal-336-rejection-fixture" }
    created_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  @{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = "MG336 MATLAB golden success rejection fixture"
    body = $Body
    prompt_summary = "MG336 rejection fixture only."
    risk = "medium"
    source = "manual"
    task_type = "matlab-parameter-sweep"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @("Reject unsafe or unsupported MG336 MATLAB success trial.")
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = $metadata
  }
}

function Assert-Rejected {
  param($Value, [string]$Expected)
  if ($Value.ok -ne $false) { throw "Expected rejection for $Expected." }
  if ([string]$Value.rejected_reason -notmatch [regex]::Escape($Expected) -and [string]$Value.validation_status -notmatch [regex]::Escape($Expected) -and @($Value.blockers) -notcontains $Expected) {
    throw "Expected rejection reason '$Expected'."
  }
}

$results = New-Object System.Collections.Generic.List[string]
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ("skybridge-matlab-success-reject-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempDir | Out-Null
try {
  $unsafeOutput = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-unsafe-output",
    "-WorkerId", "smoke-matlab-worker",
    "-OutputDir", "deploy/matlab-golden-trial"
  )
  Assert-Rejected $unsafeOutput "output_dir_outside_allowed_paths"
  Assert-False $unsafeOutput.matlab_invoked "unsafe output matlab_invoked"
  $results.Add("unsafe_output_path_rejected") | Out-Null

  $commandInputPath = Join-Path $tempDir "command-input.json"
  @{ eta = @(2, 3); h_km = @(500); P = @(6); command = "system('dir')" } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $commandInputPath -Encoding UTF8
  $commandText = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-command-text",
    "-WorkerId", "smoke-matlab-worker",
    "-InputJsonFile", $commandInputPath,
    "-OutputDir", ".agent/tmp/matlab-golden-trial/smoke-command-text"
  )
  Assert-Rejected $commandText "arbitrary_command_text_detected"
  Assert-False $commandText.matlab_invoked "command text matlab_invoked"
  $results.Add("arbitrary_command_text_rejected") | Out-Null

  $largeInputPath = Join-Path $tempDir "large-grid.json"
  @{ eta = @(1, 2, 3, 4, 5); h_km = @(500, 700); P = @(6, 8) } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $largeInputPath -Encoding UTF8
  $largeGrid = Invoke-Runner -ScriptArgs @(
    "-Command", "preview",
    "-TaskId", "smoke-large-grid",
    "-WorkerId", "smoke-matlab-worker",
    "-InputJsonFile", $largeInputPath,
    "-OutputDir", ".agent/tmp/matlab-golden-trial/smoke-large-grid"
  )
  Assert-Rejected $largeGrid "parameter_grid_too_large"
  Assert-False $largeGrid.matlab_invoked "large grid matlab_invoked"
  $results.Add("too_large_grid_rejected") | Out-Null
} finally {
  Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

try {
  Initialize-FixtureServer
  $unknown = Invoke-SuccessPreview
  Assert-Rejected $unknown "target_task_not_found"
  $results.Add("unknown_live_task_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-SuccessTaskBody -SuccessMetadata:$false) | Out-Null
  $oldResidue = Invoke-SuccessPreview
  Assert-Rejected $oldResidue "task_not_created_by_mg336_success"
  $results.Add("old_residue_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-SuccessTaskBody -TaskId "live-matlab-golden-task-333-001") | Out-Null
  $old333 = Invoke-SuccessPreview -TaskId "live-matlab-golden-task-333-001"
  Assert-Rejected $old333 "mg333_mg334_failed_tasks_must_not_be_reused"
  $results.Add("mg333_task_reuse_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-SuccessTaskBody -TaskId "live-matlab-golden-task-334-001") | Out-Null
  $old334 = Invoke-SuccessPreview -TaskId "live-matlab-golden-task-334-001"
  Assert-Rejected $old334 "mg333_mg334_failed_tasks_must_not_be_reused"
  $results.Add("mg334_task_reuse_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-FixtureServer
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-SuccessTaskBody -AllowedPaths @("deploy/**") -Body "Request mentions production deploy DNS Cloudflare OpenResty Authelia GitHub settings and server-root.") | Out-Null
  $unsafeTask = Invoke-SuccessPreview
  Assert-Rejected $unsafeTask "allowed_paths_outside_matlab_success_policy"
  if ([string]$unsafeTask.rejected_reason -notmatch "unsafe_path_or_text_detected") { throw "Expected unsafe text rejection." }
  $results.Add("unsafe_live_task_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

[pscustomobject]@{
  ok = $true
  smoke = "matlab-golden-success-reject-unsafe"
  rejected_cases = @($results.ToArray())
  unsafe_output_path_rejected = $true
  arbitrary_command_text_rejected = $true
  too_large_grid_rejected = $true
  old_residue_rejected = $true
  mg333_task_reuse_rejected = $true
  mg334_task_reuse_rejected = $true
  unknown_task_rejected = $true
  unsafe_paths_rejected = $true
  claim_created = $false
  execution_started = $false
  matlab_invoked = $false
  codex_run_called = $false
  arbitrary_shell_enabled = $false
  worker_loop_started = $false
  unbounded_run_enabled = $false
  project_control_unpaused = $false
  token_printed = $false
} | ConvertTo-Json -Depth 8 -Compress
