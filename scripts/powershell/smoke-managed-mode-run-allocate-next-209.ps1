. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"
$preview = Invoke-ManagedModeRunJson "allocate-next"
if ($preview.run_id -ne "managed-mode-run-209" -or $preview.sequence_number -ne 2) { throw "Next run must allocate managed-mode-run-209 sequence 2." }
if ($preview.selected_workunit_count -ne 1 -or $preview.selected_worker_count -ne 1) { throw "Next run preview must select exactly one workunit and worker." }
if ($preview.target_path -ne "docs/managed-mode-repeatability-orientation.md") { throw "Unexpected target path." }
Write-ManagedModeRunSmokeResult "managed-mode-run-allocate-next-209"
