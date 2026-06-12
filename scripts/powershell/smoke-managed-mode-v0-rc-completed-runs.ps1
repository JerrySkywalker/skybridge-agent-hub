. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"

$archive = Invoke-ManagedModeV0Json "completed-runs"
Assert-ManagedModeV0SafeJson $archive
if ($archive.completed_run_count -ne 3) { throw "Expected three completed managed-mode runs." }
foreach ($runId in @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210")) {
  if ($archive.completed_run_ids -notcontains $runId) { throw "Missing completed run $runId." }
}
if (@($archive.runs | Where-Object { -not $_.finalizer_evidence_sha256 }).Count -ne 0) { throw "Every completed run needs a finalizer evidence hash." }
Write-ManagedModeV0SmokeResult "managed-mode-v0-rc-completed-runs"
