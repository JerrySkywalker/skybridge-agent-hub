[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-service-doctor-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-worker-service-doctor.ps1") -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  if ($LASTEXITCODE -ne 0) { throw "worker service doctor failed" }
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $doctor = $text | ConvertFrom-Json

  if ([string]$doctor.schema -ne "skybridge.local_worker_service_doctor.v1") { throw "Unexpected doctor schema." }
  Assert-True $doctor.ok "doctor.ok"
  Assert-True $doctor.readonly "doctor.readonly"
  Assert-False $doctor.would_mutate "doctor.would_mutate"
  Assert-False $doctor.claim_enabled "doctor.claim_enabled"
  Assert-False $doctor.execute_enabled "doctor.execute_enabled"
  Assert-False $doctor.worker_loop_started "doctor.worker_loop_started"
  Assert-False $doctor.codex_executed "doctor.codex_executed"
  Assert-False $doctor.matlab_executed "doctor.matlab_executed"
  Assert-False $doctor.task_claimed "doctor.task_claimed"
  Assert-False $doctor.notification_sent "doctor.notification_sent"
  Assert-TokenPrintedFalse $doctor
  if ([string]$doctor.status.schema -ne "skybridge.local_worker_service_status.v1") { throw "Doctor missing nested status contract." }
  if ([string]$doctor.install_preview.schema -ne "skybridge.local_worker_service_install_preview.v1") { throw "Doctor missing install preview contract." }
  if ([string]$doctor.repair_preview.schema -ne "skybridge.local_worker_service_repair_preview.v1") { throw "Doctor missing repair preview contract." }
  if ([bool]$doctor.install_preview.would_mutate -or [bool]$doctor.repair_preview.would_mutate) { throw "Doctor preview nested mutation detected." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-doctor"
    schema = $doctor.schema
    readiness_status = $doctor.readiness_status
    readonly = $true
    claim_enabled = $false
    execute_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 10 -Compress
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
