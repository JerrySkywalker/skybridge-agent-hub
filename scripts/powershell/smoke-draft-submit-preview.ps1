[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-draft-submit-common.ps1"

try {
  Start-DraftSubmitSmokeServer | Out-Null
  $preview = Invoke-DraftSubmitScript -Command "sample-docs-preview"
  if ([string]$preview.schema -ne "skybridge.draft_submit_preview.v1") { throw "Unexpected submit preview schema." }
  if ([string]$preview.review_status -ne "ready_for_confirmation") { throw "Submit preview should be ready for confirmation." }
  Assert-False $preview.task_created "preview task_created"
  Assert-False $preview.campaign_created "preview campaign_created"
  Assert-DraftSubmitDisabledFlags $preview "preview"

  $tasks = Invoke-DraftSubmitJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  $campaigns = Invoke-DraftSubmitJson "GET" "/v1/campaigns?project_id=skybridge-agent-hub"
  if (@($tasks.tasks).Count -ne 0) { throw "Submit preview created tasks." }
  if (@($campaigns.campaigns).Count -ne 0) { throw "Submit preview created campaigns." }

  [pscustomobject]@{
    ok = $true
    smoke = "draft-submit-preview"
    schema = $preview.schema
    review_status = $preview.review_status
    task_created = $false
    campaign_created = $false
    claim_created = $false
    execution_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    worker_loop_started = $false
    project_control_unpause = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Stop-DraftSubmitSmokeServer
}
