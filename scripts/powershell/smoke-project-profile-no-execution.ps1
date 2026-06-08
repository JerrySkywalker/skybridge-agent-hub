$ErrorActionPreference = "Stop"
$preview = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-project-profile.ps1" -Command project-select-preview -Json | ConvertFrom-Json
foreach ($field in @("task_created", "task_claimed", "task_executed", "worker_loop_started", "queue_execution_enabled", "validation_commands_executed")) {
  if ($preview.$field -ne $false) { throw "$field must be false." }
}
$route = & pwsh -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\skybridge-worker-routing.ps1" -Command worker-route-preview -Json | ConvertFrom-Json
if ($route.task.project_selection_preview_only -ne $true) { throw "Worker route preview must include project selection preview-only metadata." }
if ($route.task_claimed -ne $false -or $route.task_executed -ne $false -or $route.worker_loop_started -ne $false) { throw "Worker route preview must not execute." }
[pscustomobject]@{ ok = $true; scenario = "project-profile-no-execution"; token_printed = $false } | ConvertTo-Json -Compress
