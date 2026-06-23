[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

$LiveTaskId = "live-safe-template-task-332-001"
$LiveBlockedPaths = @(".env", "secrets/**", "deploy/**", ".git/**", "server-root", "DNS", "Cloudflare", "OpenResty", "Authelia", "GitHub settings", "production infrastructure")

function Initialize-LiveRejectFixture {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG332 Live Safe Task Rejection Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "node")
    labels = @("mg332-fixture", "reject-unsafe")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{
    status_note = "mg332 reject fixture ready"
    load = 0
  } | Out-Null
}

function New-LiveTaskBody {
  param(
    [string]$TemplateId = "safe-local-smoke.v1",
    [string]$RunnerId = "safe-local-smoke-runner.v1",
    [string[]]$RequiredCapabilities = @("windows", "powershell", "node"),
    [string[]]$AllowedPaths = @(".agent/tmp/**"),
    [string]$Body = "Run the fixed MG332 safe-local-smoke fixture only.",
    [bool]$PilotMetadata = $true
  )
  $metadata = @{
    adapter = if ($PilotMetadata) { "mg332-live-safe-task-pilot" } else { "mg332-live-safe-task-rejection-fixture" }
    decision = "continue"
    reason = if ($PilotMetadata) { "mg332_one_live_safe_template_task" } else { "mg332_rejection_fixture" }
    task_type = "safe-local-smoke"
    template_id = $TemplateId
    runner_id = $RunnerId
    evidence_schema = @("skybridge.live_safe_template_task_evidence.v1")
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($LiveBlockedPaths)
    validation = @("Reject unsafe or unsupported MG332 live template.")
    expected_outputs = @(".agent/tmp/live-safe-template-task-332/**")
    stop_criteria_status = @("reject_without_claim")
    source_run_id = if ($PilotMetadata) { "mega-goal-332-live-safe-task-pilot" } else { "mega-goal-332-rejection-fixture" }
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  }
  @{
    task_id = $LiveTaskId
    project_id = "skybridge-agent-hub"
    title = "MG332 live safe template rejection fixture"
    body = $Body
    prompt_summary = "MG332 rejection fixture only."
    risk = "low"
    source = "manual"
    task_type = "safe-local-smoke"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($LiveBlockedPaths)
    validation = @("Reject unsafe or unsupported MG332 live template.")
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = $metadata
  }
}

function Invoke-LivePreview {
  param([int]$MaxTasks = 1, [string]$TaskId = $LiveTaskId)
  Invoke-WorkerTemplateRunnerScript `
    -Command "preview-live-one" `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId $TaskId `
    -TemplateId "safe-local-smoke.v1" `
    -MaxTasks $MaxTasks
}

function Assert-RejectReason {
  param($Preview, [string]$Expected)
  if ($Preview.ok -ne $false) { throw "Expected preview rejection for $Expected." }
  if ([string]$Preview.rejected_reason -notmatch [regex]::Escape($Expected)) {
    throw "Expected rejection reason '$Expected', got '$($Preview.rejected_reason)'."
  }
  Assert-RunnerNoClaimOrExecution $Preview "reject $Expected"
}

$results = New-Object System.Collections.Generic.List[object]

try {
  Initialize-LiveRejectFixture
  $maxTasks = Invoke-LivePreview -MaxTasks 2
  Assert-RejectReason $maxTasks "max_tasks_exceeds_mg332_live_limit"
  $results.Add("max_tasks_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  $unknown = Invoke-LivePreview
  Assert-RejectReason $unknown "target_task_not_found"
  $results.Add("unknown_task_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-LiveTaskBody -PilotMetadata:$false) | Out-Null
  $oldResidue = Invoke-LivePreview
  Assert-RejectReason $oldResidue "task_not_created_by_mg332_pilot"
  $results.Add("old_residue_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-LiveTaskBody -TemplateId "matlab-result-analysis.v1" -RunnerId "matlab-result-analysis-runner.v1" -RequiredCapabilities @("matlab")) | Out-Null
  $matlab = Invoke-LivePreview
  Assert-RejectReason $matlab "template_not_supported_mg332_live"
  $results.Add("matlab_template_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-LiveTaskBody -TemplateId "codex-analysis-report.v1" -RunnerId "codex-analysis-report-runner.v1" -RequiredCapabilities @("codex", "git")) | Out-Null
  $codex = Invoke-LivePreview
  Assert-RejectReason $codex "template_not_supported_mg332_live"
  $results.Add("codex_template_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-LiveTaskBody -AllowedPaths @("deploy/**") -Body "Request mentions production deploy DNS Cloudflare OpenResty Authelia GitHub settings and server-root.") | Out-Null
  $unsafe = Invoke-LivePreview
  Assert-RejectReason $unsafe "allowed_paths_outside_live_policy"
  if ([string]$unsafe.rejected_reason -notmatch "unsafe_path_or_text_detected") { throw "Expected unsafe text rejection." }
  $results.Add("unsafe_paths_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

try {
  Initialize-LiveRejectFixture
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" (New-LiveTaskBody) | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks/$LiveTaskId/claim" @{ worker_id = "jerry-win-local-01" } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks/$LiveTaskId/start" @{ worker_id = "jerry-win-local-01" } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks/$LiveTaskId/complete" @{
    worker_id = "jerry-win-local-01"
    summary = "Fixture completion before old residue preview."
    evidence_summary = @{
      task_id = $LiveTaskId
      summary = "Fixture completed before rejection preview."
      validation_status = "passed"
      changed_files = @()
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  } | Out-Null
  $terminal = Invoke-LivePreview
  Assert-RejectReason $terminal "target_task_terminal_or_blocked"
  $results.Add("terminal_residue_rejected") | Out-Null
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}

[pscustomobject]@{
  ok = $true
  smoke = "live-safe-task-pilot-reject-unsafe"
  rejected_cases = @($results.ToArray())
  max_tasks_over_one_rejected = $true
  old_residue_rejected = $true
  unknown_task_rejected = $true
  matlab_templates_rejected = $true
  codex_templates_rejected = $true
  unsafe_paths_rejected = $true
  production_control_plane_rejected = $true
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
