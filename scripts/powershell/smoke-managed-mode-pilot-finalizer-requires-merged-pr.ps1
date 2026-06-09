. "$PSScriptRoot\smoke-managed-mode-v1-common.ps1"
$stateDir = New-ManagedModePilotSmokeStateDir
try {
  Write-ManagedModePilotFixtureEvidence -StateDir $stateDir
  $preview = Invoke-ManagedModePilotJson "finalizer-preview" "low-docs" @("-StateDir", $stateDir)
  if ($preview.final_state -ne "held_waiting_human_pr_review") { throw "Finalizer should hold until the task PR is merged." }
  if (@($preview.blockers) -notcontains "pilot_task_pr_not_merged" -and @($preview.blockers) -notcontains "pilot_task_pr_missing") { throw "Merged PR blocker missing." }
  Assert-ManagedModeSafeJson $preview
  Write-ManagedModeSmokeResult "managed-mode-pilot-finalizer-requires-merged-pr"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
