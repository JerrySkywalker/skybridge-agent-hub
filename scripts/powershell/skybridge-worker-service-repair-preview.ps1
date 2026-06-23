[CmdletBinding()]
param(
  [string]$ServiceName = "SkyBridgeWorkerService",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

$statusArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1"), "-ServiceName", $ServiceName, "-Json")
if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) { $statusArgs += @("-HomeRoot", $HomeRoot) }
if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $statusArgs += @("-RepoRoot", $RepoRoot) }
$status = (& pwsh @statusArgs | Out-String).Trim() | ConvertFrom-Json

$planned = New-Object System.Collections.Generic.List[string]
if (-not [bool]$status.service_installed) {
  $planned.Add("run_install_preview_first") | Out-Null
} else {
  if (-not [bool]$status.service_running) { $planned.Add("inspect_service_start_without_starting_loop") | Out-Null }
  if ([string]$status.service_start_type -eq "Disabled") { $planned.Add("future_apply_would_set_manual_start_type_after_confirmation") | Out-Null }
}
if (-not [bool]$status.api_base_configured) { $planned.Add("repair_missing_api_base_config_template") | Out-Null }
if (-not [bool]$status.token_file_present) { $planned.Add("repair_missing_worker_token_file_guidance") | Out-Null }
if (-not [bool]$status.git_available -or -not [bool]$status.node_available -or -not [bool]$status.pnpm_available) {
  $planned.Add("repair_required_tool_installation_guidance") | Out-Null
}
if ($planned.Count -eq 0) { $planned.Add("no_repair_changes_needed") | Out-Null }

$report = [pscustomobject]@{
  schema = "skybridge.local_worker_service_repair_preview.v1"
  ok = $true
  mode = "preview"
  service_name = $ServiceName
  worker_id = $status.worker_id
  status = $status
  planned_actions = @($planned)
  would_mutate = $false
  no_mutation = $true
  apply_supported = $false
  apply_status = "future_work"
  confirmation_required_for_future_apply = "CONFIRM SKYBRIDGE LOCAL WORKER SERVICE REPAIR"
  claim_enabled = $false
  execute_enabled = $false
  worker_loop_started = $false
  codex_executed = $false
  matlab_executed = $false
  task_claimed = $false
  notification_sent = $false
  token_printed = $false
}

if ($Json) {
  $report | ConvertTo-Json -Depth 30 -Compress
} else {
  "Repair preview for $ServiceName"
  "Would mutate: false"
  "Planned actions: $($report.planned_actions -join ', ')"
  "Apply: future_work"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
