. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
$matrix = Invoke-BoincV1PreviewJson -Command "action-matrix"
$required = @("preview", "pause", "drain", "resume_preview_only", "emergency_stop_preview", "apply_disabled")
foreach ($actionName in $required) {
  $action = $matrix.actions | Where-Object { $_.action -eq $actionName } | Select-Object -First 1
  Assert-True ($null -ne $action) "Missing action $actionName."
  Assert-False ([bool]$action.enabled) "Action $actionName must be disabled."
  Assert-True ([bool]$action.preview_only) "Action $actionName must be preview-only."
  Assert-False ([bool]$action.apply_enabled) "Action $actionName must not enable apply."
}
Assert-True ([bool]$matrix.all_actions_preview_only) "All actions must be preview-only."
Assert-False ([bool]$matrix.worker_started) "Action matrix must not start worker."
Assert-False ([bool]$matrix.task_created) "Action matrix must not create tasks."
Write-SmokeResult "boinc-v1-action-matrix-preview-only"
