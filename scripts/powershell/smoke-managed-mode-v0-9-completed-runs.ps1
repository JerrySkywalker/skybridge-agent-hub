. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$archive = Invoke-ManagedModeV0Json "completed-runs"
foreach ($id in @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")) {
  if (@($archive.completed_run_ids) -notcontains $id) { throw "Missing completed run $id." }
}
if ($archive.docs_local_smoke_run_count_after_pilot -ne 3) { throw "Expected three post-pilot docs/local-smoke runs." }
Assert-ManagedModeV0SafeJson $archive
Write-ManagedModeV0SmokeResult "managed-mode-v0-9-completed-runs"
