. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$state = Invoke-ManagedModeRunJson "run-failure-state"
if ($state.classification -notin @("invocation_failed_no_mutation", "run_failed_no_mutation")) { throw "Expected no-mutation failure classification, got $($state.classification)." }
if ($state.codex_execution_started -ne $true) { throw "Expected prior Codex execution started." }
if ($state.previous_changed_file_count -ne 0) { throw "Expected no changed files." }
if ($state.pr_created -ne $false) { throw "Expected no PR." }
Assert-ManagedModeRunSafeJson $state
Write-ManagedModeRunSmokeResult "managed-mode-run-classifies-209b-failure-no-mutation"
