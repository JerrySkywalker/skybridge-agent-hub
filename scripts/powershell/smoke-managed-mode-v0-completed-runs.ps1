. "$PSScriptRoot/smoke-managed-mode-v0-common.ps1"
$archive = Invoke-ManagedModeV0Json "completed-runs"
if ($archive.completed_run_count -ne 4) { throw "Expected exactly four completed runs." }
foreach ($id in @("managed-mode-pilot-208", "managed-mode-run-209", "managed-mode-run-210", "managed-mode-run-211")) {
  if (@($archive.completed_run_ids) -notcontains $id) { throw "Missing completed run $id." }
}
if ($archive.docs_local_smoke_run_count_after_pilot -ne 3) { throw "Expected three post-pilot docs/local-smoke runs." }
foreach ($file in @("docs/managed-mode-pilot-orientation.md", "docs/managed-mode-repeatability-orientation.md", "docs/managed-mode-v0-operator-checklist.md", "docs/managed-mode-v0-repeatability-check.md")) {
  if (@($archive.changed_files) -notcontains $file) { throw "Missing changed file $file." }
}
if (@($archive.runs | Where-Object { -not $_.finalizer_evidence_sha256 }).Count -ne 0) { throw "Every completed run needs a finalizer evidence hash." }
Assert-ManagedModeV0SafeJson $archive
Write-ManagedModeV0SmokeResult "managed-mode-v0-completed-runs"
