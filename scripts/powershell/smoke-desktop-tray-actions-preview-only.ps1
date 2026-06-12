$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "local-supervisor-smoke-common.ps1")
$matrix = Invoke-LocalSupervisorSmokeCommand -Command "action-matrix"
foreach ($action in $matrix.actions) {
  if ($action.preview_only -ne $true) { throw "Tray action is not preview-only: $($action.id)" }
  if ($action.execution_enabled -ne $false -or $action.task_claim_enabled -ne $false -or $action.queue_apply_enabled -ne $false) {
    throw "Tray action enables unsafe behavior: $($action.id)"
  }
}
[pscustomobject]@{ ok = $true; scenario = "desktop-tray-actions-preview-only"; token_printed = $false } | ConvertTo-Json -Compress
