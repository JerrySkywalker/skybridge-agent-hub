. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$plan = Invoke-ManagedModePilotJson "plan-preview"
$policy = $plan.policy
foreach ($field in @("max_workunits", "max_tasks", "max_claims", "max_codex_executions", "max_prs")) {
  if ([int]$policy.$field -ne 1) { throw "$field must equal 1." }
}
if (-not $policy.stop_on_pr_created -or -not $policy.require_human_review) { throw "Pilot stop/review flags missing." }
if ($policy.general_bounded_queue_apply_enabled -ne $false) { throw "General apply must be false in policy." }
Write-ManagedModeSmokeResult "managed-mode-v1-pilot-policy-contract"
