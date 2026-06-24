[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-worker-template-runner-common.ps1"

function Invoke-MatlabSuccess {
  param([string]$Command)
  $scriptPath = Join-Path $PSScriptRoot "skybridge-live-matlab-golden-success.ps1"
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $scriptPath `
    -Command $Command `
    -ApiBase $script:WorkerTemplateRunnerApiBase `
    -WorkerId "jerry-win-local-01" `
    -ProjectId "skybridge-agent-hub" `
    -TaskId "live-matlab-golden-task-336-001" `
    -TemplateId "matlab-parameter-sweep.v1" `
    -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $text | ConvertFrom-Json
}

try {
  Start-WorkerTemplateRunnerSmokeServer | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/projects" @{
    project_id = "skybridge-agent-hub"
    name = "MG336 MATLAB Success Preview Fixture"
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/register" @{
    worker_id = "jerry-win-local-01"
    name = "Jerry Windows Local Worker"
    provider = "local-windows"
    capabilities = @("windows", "powershell", "matlab")
    labels = @("mg336-fixture", "matlab-success")
    enabled = $true
  } | Out-Null
  Invoke-WorkerTemplateRunnerJson "POST" "/v1/workers/jerry-win-local-01/heartbeat" @{
    status_note = "mg336 preview fixture ready"
    load = 0
  } | Out-Null

  $status = Invoke-MatlabSuccess -Command "status"
  if ([string]$status.schema -ne "skybridge.live_matlab_golden_success_status.v1") { throw "Unexpected status schema." }
  Assert-False $status.claim_created "status claim_created"
  Assert-False $status.execution_started "status execution_started"
  Assert-TokenPrintedFalse $status

  $doctor = Invoke-MatlabSuccess -Command "doctor-preview"
  if ([string]$doctor.schema -ne "skybridge.matlab_doctor.v1") { throw "Unexpected doctor preview schema." }
  Assert-False $doctor.matlab_invoked "doctor-preview matlab_invoked"
  Assert-TokenPrintedFalse $doctor

  $previewCreate = Invoke-MatlabSuccess -Command "preview-create"
  if ([string]$previewCreate.schema -ne "skybridge.live_matlab_golden_success_create_preview.v1") { throw "Unexpected create preview schema." }
  if ($previewCreate.ok -ne $true) { throw "Create preview should be ok in fixture: $($previewCreate.blockers -join ';')" }
  if ($previewCreate.would_create_task -ne $true) { throw "Create preview should report would_create_task." }
  Assert-False $previewCreate.task_created "preview-create task_created"
  Assert-False $previewCreate.claim_created "preview-create claim_created"
  Assert-False $previewCreate.execution_started "preview-create execution_started"
  Assert-TokenPrintedFalse $previewCreate

  $tasksAfterPreview = Invoke-WorkerTemplateRunnerJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  if (@($tasksAfterPreview.tasks).Count -ne 0) { throw "preview-create should not create tasks." }

  $previewRun = Invoke-MatlabSuccess -Command "preview-run"
  if ([string]$previewRun.schema -ne "skybridge.live_matlab_golden_success_run_preview.v1") { throw "Unexpected run preview schema." }
  if ($previewRun.ok -ne $false) { throw "preview-run should fail closed when target task is missing." }
  if ([string]$previewRun.rejected_reason -notmatch "target_task_not_found") { throw "preview-run should report target_task_not_found." }
  Assert-False $previewRun.claim_created "preview-run claim_created"
  Assert-False $previewRun.execution_started "preview-run execution_started"
  Assert-False $previewRun.worker_loop_started "preview-run worker_loop_started"
  Assert-False $previewRun.codex_run_called "preview-run codex_run_called"
  Assert-False $previewRun.arbitrary_shell_enabled "preview-run arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $previewRun

  [pscustomobject]@{
    ok = $true
    smoke = "matlab-golden-success-preview"
    status_schema = $status.schema
    doctor_preview_schema = $doctor.schema
    preview_create_schema = $previewCreate.schema
    preview_run_schema = $previewRun.schema
    task_created = $false
    claim_created = $false
    execution_started = $false
    matlab_invoked = $false
    codex_run_called = $false
    arbitrary_shell_enabled = $false
    worker_loop_started = $false
    project_control_unpaused = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-WorkerTemplateRunnerSmokeServer
}
