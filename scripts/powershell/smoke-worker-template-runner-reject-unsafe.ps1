[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

function New-RejectedTask {
  param(
    [string]$TaskId,
    [string]$Title,
    [string]$Body,
    [string]$TemplateId,
    [string]$RunnerId,
    [string[]]$RequiredCapabilities,
    [string[]]$AllowedPaths = @("scripts/powershell/smoke-worker-template-runner-preview.ps1", "tests/fixtures/worker-template-runner"),
    [string[]]$BlockedPaths = @("production", "deploy", "server-root", ".env", "secrets", ".git", "GitHub settings")
  )
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/tasks" @{
    task_id = $TaskId
    project_id = "skybridge-agent-hub"
    title = $Title
    body = $Body
    prompt_summary = "MG329 rejection fixture only."
    risk = "low"
    source = "manual"
    task_type = "local-validation"
    allowed_paths = @($AllowedPaths)
    blocked_paths = @($BlockedPaths)
    validation = @("Reject unsafe or unsupported MG329 template.")
    required_capabilities = @($RequiredCapabilities)
    planner_metadata = @{
      adapter = "mg329-worker-template-runner-rejection-fixture"
      decision = "continue"
      reason = "mg329_rejection_fixture"
      task_type = "local-validation"
      template_id = $TemplateId
      runner_id = $RunnerId
      evidence_schema = @("skybridge.local_smoke_evidence.v1")
      allowed_paths = @($AllowedPaths)
      blocked_paths = @($BlockedPaths)
      validation = @("Reject unsafe or unsupported MG329 template.")
      expected_files = @()
      expected_outputs = @()
      stop_criteria_status = @("reject_without_claim")
      created_at = (Get-Date).ToUniversalTime().ToString("o")
    }
  } | Out-Null
}

try {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG329 Worker Template Runner Rejection Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "mg329-worker-template-runner"
    name = "MG329 rejection fixture worker"
    provider = "local-powershell"
    capabilities = @("powershell", "node", "pnpm")
    labels = @("mg329-fixture", "reject-unsafe")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/mg329-worker-template-runner/heartbeat" @{
    status_note = "mg329 rejection fixture ready"
    load = 0
  } | Out-Null

  New-RejectedTask `
    -TaskId "mg329-reject-matlab-template" `
    -Title "MG329 reject MATLAB template" `
    -Body "Unsupported template fixture." `
    -TemplateId "matlab-result-analysis.v1" `
    -RunnerId "matlab-result-analysis-runner.v1" `
    -RequiredCapabilities @("matlab")
  New-RejectedTask `
    -TaskId "mg329-reject-codex-template" `
    -Title "MG329 reject Codex report template" `
    -Body "Unsupported template fixture." `
    -TemplateId "codex-analysis-report.v1" `
    -RunnerId "codex-analysis-report-runner.v1" `
    -RequiredCapabilities @("codex", "git")
  New-RejectedTask `
    -TaskId "mg329-reject-unknown-template" `
    -Title "MG329 reject unknown template" `
    -Body "Unknown template fixture." `
    -TemplateId "unknown-template.v1" `
    -RunnerId "unknown-runner.v1" `
    -RequiredCapabilities @("powershell", "node", "pnpm")
  New-RejectedTask `
    -TaskId "mg329-reject-unsafe-paths" `
    -Title "MG329 reject unsafe control-plane request" `
    -Body "Request mentions production deploy DNS Cloudflare OpenResty Authelia GitHub settings and server-root." `
    -TemplateId "safe-local-smoke.v1" `
    -RunnerId "safe-local-smoke-runner.v1" `
    -RequiredCapabilities @("powershell", "node", "pnpm") `
    -AllowedPaths @("deploy/**")

  $preview = Invoke-WorkerTemplateRunnerScript -Command "preview"
  if ([string]$preview.schema -ne "skybridge.worker_template_runner_preview.v1") { throw "Unexpected runner preview schema." }
  if ($preview.ok -ne $false) { throw "Unsafe/unsupported fixture should not select a task." }
  if ([string]$preview.rejected_reason -ne "no_eligible_template_task") { throw "Expected no eligible template task." }
  Assert-False $preview.selected "reject preview selected"
  Assert-False $preview.eligible "reject preview eligible"
  Assert-RunnerNoClaimOrExecution $preview "reject preview"

  $reasons = @($preview.rejected_tasks | ForEach-Object { [string]$_.rejected_reason })
  foreach ($expected in @(
    "matlab_template_rejected_mg329",
    "codex_or_docs_runner_deferred_mg329",
    "unknown_template_id",
    "unsafe_path_or_text_detected",
    "allowed_paths_outside_template_policy"
  )) {
    if (-not (($reasons -join ";") -match [regex]::Escape($expected))) {
      throw "Expected rejection reason missing: $expected"
    }
  }

  foreach ($taskId in @(
    "mg329-reject-matlab-template",
    "mg329-reject-codex-template",
    "mg329-reject-unknown-template",
    "mg329-reject-unsafe-paths"
  )) {
    $task = (Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks/$([uri]::EscapeDataString($taskId))").task
    if ([string]$task.status -ne "queued") { throw "Rejected task status mutated: $taskId" }
    if ($task.claim) { throw "Rejected task was claimed: $taskId" }
    if ($task.assigned_worker_id) { throw "Rejected task was assigned: $taskId" }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-template-runner-reject-unsafe"
    schema = $preview.schema
    rejected_count = @($preview.rejected_tasks).Count
    matlab_templates_rejected = $true
    codex_templates_rejected = $true
    unknown_templates_rejected = $true
    unsafe_paths_rejected = $true
    production_control_plane_rejected = $true
    claim_created = $false
    execution_started = $false
    execution_completed = $false
    execution_failed = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    unbounded_run_enabled = $false
    project_control_unpaused = $false
    old_task_requeued = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}
