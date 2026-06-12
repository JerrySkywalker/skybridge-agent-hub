. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$archive = Invoke-ManagedModeV0Json "completed-runs"
if ($archive.completed_run_count -ne 2) { throw "Expected exactly two completed runs." }
foreach ($id in @("managed-mode-pilot-208", "managed-mode-run-209")) {
  if (@($archive.completed_run_ids) -notcontains $id) { throw "Missing completed run $id." }
}
foreach ($file in @("docs/managed-mode-pilot-orientation.md", "docs/managed-mode-repeatability-orientation.md")) {
  if (@($archive.changed_files) -notcontains $file) { throw "Missing changed file $file." }
}
if (@($archive.runs | Where-Object { -not $_.finalizer_evidence_sha256 }).Count -ne 0) { throw "Every completed run needs a finalizer evidence hash." }
Assert-ManagedModeV0SafeJson $archive
Write-ManagedModeV0SmokeResult "managed-mode-v0-completed-runs"
