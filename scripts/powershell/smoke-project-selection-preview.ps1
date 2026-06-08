$ErrorActionPreference = "Stop"
$result = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-select-preview -Json | ConvertFrom-Json
if ($result.project_selection_preview_only -ne $true) { throw "Project selection must be preview-only." }
foreach ($field in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "queue_execution_enabled", "validation_commands_executed", "token_printed")) {
  if ($result.$field -ne $false) { throw "$field must be false." }
}
[pscustomobject]@{ ok = $true; scenario = "project-selection-preview"; profile_hash = $result.profile_hash; token_printed = $false } | ConvertTo-Json -Compress
