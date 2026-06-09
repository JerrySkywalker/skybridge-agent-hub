[CmdletBinding()]
param([switch]$Json)
. "$PSScriptRoot\smoke-workunit-common.ps1"
$plan = Invoke-WorkunitQueue -Command preview
$policy = $plan.policy
foreach ($field in @("max_steps", "max_tasks", "max_prs", "max_runtime_minutes", "max_parallel_per_repo", "stop_on_pr_created", "stop_on_ci_failure", "stop_on_warning", "drain_after_current", "pause_after_current", "require_human_review", "allow_task_types", "block_task_types")) {
  if (-not $policy.PSObject.Properties[$field]) { throw "Policy missing $field." }
}
if ($policy.max_tasks -gt 1 -or $policy.max_prs -ne 0 -or -not $policy.require_human_review) { throw "Unexpected bounded queue policy." }
Assert-TokenPrintedFalse $policy
[pscustomobject]@{ ok = $true; scenario = "bounded-queue-policy-contract"; token_printed = $false } | ConvertTo-Json -Compress
