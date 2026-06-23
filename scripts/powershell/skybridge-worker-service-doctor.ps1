[CmdletBinding()]
param(
  [string]$ServiceName = "SkyBridgeWorkerService",
  [string]$HomeRoot,
  [string]$RepoRoot,
  [switch]$Json
)

$ErrorActionPreference = "Stop"

function Invoke-WorkerServiceJsonScript {
  param([string]$ScriptName)
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot $ScriptName), "-ServiceName", $ServiceName, "-Json")
  if (-not [string]::IsNullOrWhiteSpace($HomeRoot)) { $args += @("-HomeRoot", $HomeRoot) }
  if (-not [string]::IsNullOrWhiteSpace($RepoRoot)) { $args += @("-RepoRoot", $RepoRoot) }
  ((& pwsh @args | Out-String).Trim() | ConvertFrom-Json)
}

$status = Invoke-WorkerServiceJsonScript "skybridge-worker-service-status.ps1"
$installPreview = Invoke-WorkerServiceJsonScript "skybridge-worker-service-install-preview.ps1"
$repairPreview = Invoke-WorkerServiceJsonScript "skybridge-worker-service-repair-preview.ps1"

$checks = @(
  [pscustomobject]@{ name = "status_schema"; ok = ([string]$status.schema -eq "skybridge.local_worker_service_status.v1"); severity = "blocker" },
  [pscustomobject]@{ name = "service_installed"; ok = [bool]$status.service_installed; severity = "blocker" },
  [pscustomobject]@{ name = "api_base_configured"; ok = [bool]$status.api_base_configured; severity = "blocker" },
  [pscustomobject]@{ name = "token_file_present"; ok = [bool]$status.token_file_present; severity = "blocker" },
  [pscustomobject]@{ name = "required_tools"; ok = ([bool]$status.powershell_available -and [bool]$status.git_available -and [bool]$status.node_available -and [bool]$status.pnpm_available); severity = "blocker" },
  [pscustomobject]@{ name = "codex_capability"; ok = [bool]$status.codex_available; severity = "warning" },
  [pscustomobject]@{ name = "matlab_capability"; ok = [bool]$status.matlab_available; severity = "warning" },
  [pscustomobject]@{ name = "no_execution_enabled"; ok = (-not [bool]$status.claim_enabled -and -not [bool]$status.execute_enabled -and -not [bool]$status.worker_loop_started); severity = "blocker" },
  [pscustomobject]@{ name = "token_printed_false"; ok = ([bool]$status.token_printed -eq $false); severity = "blocker" }
)

$report = [pscustomobject]@{
  schema = "skybridge.local_worker_service_doctor.v1"
  ok = $true
  mode = "readonly"
  service_name = $ServiceName
  worker_id = $status.worker_id
  readiness_status = $status.readiness_status
  checks = $checks
  status = $status
  install_preview = $installPreview
  repair_preview = $repairPreview
  blockers = @($status.blockers)
  warnings = @($status.warnings)
  recommended_next_action = $status.recommended_next_action
  readonly = $true
  would_mutate = $false
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
  $report | ConvertTo-Json -Depth 40 -Compress
} else {
  "Worker service doctor: $($report.readiness_status)"
  "Blockers: $($report.blockers -join ', ')"
  "Warnings: $($report.warnings -join ', ')"
  "Next: $($report.recommended_next_action)"
  "claim_enabled=false execute_enabled=false worker_loop_started=false token_printed=false"
}
