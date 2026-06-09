. "$PSScriptRoot/smoke-boinc-manager-common.ps1"
$matrix = Invoke-BoincManagerJson "action-matrix"
$disabled = @($matrix.disabled | ForEach-Object { $_.action })
foreach ($action in @("start_one_apply", "start_queue_apply", "bounded_queue_apply", "start_all", "resume_execution", "worker_claim", "task_execution", "auto_merge")) {
  if ($disabled -notcontains $action) { throw "Expected disabled action $action." }
}
if ($matrix.task_created -or $matrix.task_claimed -or $matrix.task_executed -or $matrix.pr_created) { throw "Action matrix must not create work." }
Write-SmokeResult "boinc-manager-action-matrix"
