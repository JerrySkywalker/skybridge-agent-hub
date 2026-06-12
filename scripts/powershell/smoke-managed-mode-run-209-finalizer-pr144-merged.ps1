. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$preview = Invoke-ManagedModeRunJson "run-finalizer-preview"
if ($preview.run_id -ne "managed-mode-run-209") { throw "Unexpected run id." }
if ($preview.task_pr.url -ne "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/144") { throw "Expected PR #144 URL." }
if ($preview.task_pr.merged -ne $true) { throw "Expected PR #144 merged." }
if ($preview.changed_file_exists_on_main -ne $true) { throw "Expected repeatability orientation file on main." }
Assert-ManagedModeRunSafeJson $preview
Write-ManagedModeRunSmokeResult "managed-mode-run-209-finalizer-pr144-merged"
