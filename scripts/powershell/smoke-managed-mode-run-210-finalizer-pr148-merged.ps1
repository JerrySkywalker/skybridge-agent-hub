. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$state = Invoke-ManagedModeRunJson "run-finalizer-preview" -Extra @(
  "-ManagedModeRunId", "managed-mode-run-210",
  "-SequenceNumber", "3",
  "-TargetPath", "docs/managed-mode-v0-operator-checklist.md",
  "-StateDir", ".agent/tmp/managed-mode-run-210"
)
if ($state.task_pr.url -ne "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/148") { throw "Expected PR #148." }
if ($state.task_pr.merged -ne $true -or $state.task_pr.merge_commit -ne "cb0eec4d77234e740b747387afe96b1f9eadfaea") { throw "Expected merged PR #148 with merge commit." }
Write-ManagedModeRunSmokeResult "managed-mode-run-210-finalizer-pr148-merged"
