$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$summary = Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "safe-summary")
Assert-Truthy $summary.ok "ok"
if ($summary.default_provider_id -ne "mock") { throw "Default provider must be mock." }
Assert-Truthy $summary.hermes_disabled_by_default "hermes_disabled_by_default"
Assert-Truthy $summary.ci_disables_live_call "ci_disables_live_call"
Assert-False $summary.hermes_live_call_enabled "hermes_live_call_enabled"
Assert-False $summary.raw_request_persisted "raw_request_persisted"
Assert-False $summary.raw_response_persisted "raw_response_persisted"
Assert-False $summary.output_executed "output_executed"
Assert-False $summary.worker_execution_started "worker_execution_started"
Assert-False $summary.workunit_created "workunit_created"
Assert-False $summary.task_created "task_created"
Assert-False $summary.task_pr_created "task_pr_created"
Assert-False $summary.queue_apply_enabled "queue_apply_enabled"
Write-Host "[smoke-manual-task-provider-contract] ok"
