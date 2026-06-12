. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$state = Invoke-ManagedModeRunJson "run-finalizer-preview" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-211",
  "-SequenceNumber", "4",
  "-TargetPath", "docs/managed-mode-v0-repeatability-check.md",
  "-StateDir", ".agent/tmp/managed-mode-run-211"
)
if (-not $state.task_pr.merged) { throw "Expected PR #151 to be merged." }
if ($state.task_pr.url -ne "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/151") { throw "Expected PR #151 URL." }
if ($state.task_pr.merge_commit -ne "46add782968e7475a875249d48da0c1c16417dad") { throw "Expected PR #151 merge commit." }
Assert-ManagedModeRunSafeJson $state
Write-ManagedModeRunSmokeResult "managed-mode-run-211-finalizer-pr-merged"
