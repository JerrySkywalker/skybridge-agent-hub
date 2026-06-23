[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-draft-submit-common.ps1"

$ConfirmationPhrase = "I_UNDERSTAND_CREATE_QUEUED_DRAFT_RECORDS_ONLY_NO_EXECUTION"

try {
  Start-DraftSubmitSmokeServer | Out-Null
  $matlabFile = New-DraftSubmitInputFile -Kind "sample-matlab"

  $preview = Invoke-DraftSubmitScript -Command "preview" -InputJsonFile $matlabFile
  if ([string]$preview.template_id -ne "matlab-parameter-sweep.v1") { throw "MATLAB submit preview template mismatch." }
  Assert-False $preview.task_created "matlab preview task_created"
  Assert-False $preview.campaign_created "matlab preview campaign_created"
  Assert-DraftSubmitDisabledFlags $preview "matlab preview"

  $submitted = Invoke-DraftSubmitScript -Command "submit" -InputJsonFile $matlabFile -Confirm -ConfirmationText $ConfirmationPhrase
  if ($submitted.campaign_created -ne $true) { throw "Confirmed MATLAB draft did not create a campaign." }
  Assert-False $submitted.task_created "matlab submit task_created"
  Assert-DraftSubmitDisabledFlags $submitted "matlab submit"
  if (-not $submitted.created_campaign_id) { throw "MATLAB submit missing campaign id." }
  if (@($submitted.created_campaign_step_ids).Count -lt 5) { throw "MATLAB submit missing expected campaign steps." }

  $campaign = Invoke-DraftSubmitJson "GET" "/v1/campaigns/$($submitted.created_campaign_id)"
  if ([string]$campaign.campaign.status -eq "running") { throw "Submitted campaign must not be running." }
  if (@($campaign.steps | Where-Object { [string]$_.status -eq "running" }).Count -ne 0) { throw "Submitted campaign step must not be running." }
  foreach ($goalId in @("prepare-parameter-grid", "run-matlab-sweep", "aggregate-results", "generate-analysis-report", "hold-for-operator-review")) {
    if (@($campaign.steps | ForEach-Object { [string]$_.goal_id }) -notcontains $goalId) { throw "Missing MATLAB campaign step $goalId." }
  }
  $tasks = Invoke-DraftSubmitJson "GET" "/v1/tasks?project_id=skybridge-agent-hub"
  if (@($tasks.tasks).Count -ne 0) { throw "MATLAB campaign submit should not create tasks." }

  [pscustomobject]@{
    ok = $true
    smoke = "draft-submit-matlab-campaign"
    created_campaign_id = $submitted.created_campaign_id
    created_campaign_step_count = @($submitted.created_campaign_step_ids).Count
    campaign_status = $campaign.campaign.status
    task_created = $false
    campaign_created = $true
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
