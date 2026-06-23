[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-service-status-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $statusRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -HomeRoot $tempHome -RepoRoot $RepoRoot -ForceMissingTool @("codex", "matlab") -Json
  Assert-NoUnsafeText (($statusRaw | Out-String).Trim())
  $status = (($statusRaw | Out-String).Trim() | ConvertFrom-Json)

  if ([string]$status.schema -ne "skybridge.local_worker_service_status.v1") { throw "Unexpected status schema." }
  Assert-True $status.ok "status.ok"
  Assert-False $status.claim_enabled "claim_enabled"
  Assert-False $status.execute_enabled "execute_enabled"
  Assert-False $status.worker_loop_started "worker_loop_started"
  Assert-TokenPrintedFalse $status
  foreach ($field in @(
    "worker_id",
    "service_name",
    "service_installed",
    "service_running",
    "service_start_type",
    "api_base_configured",
    "token_file_present",
    "repo_root_detected",
    "powershell_available",
    "git_available",
    "gh_available",
    "node_available",
    "pnpm_available",
    "codex_available",
    "matlab_available",
    "capabilities",
    "readiness_status",
    "blockers",
    "warnings",
    "recommended_next_action"
  )) {
    if ($status.PSObject.Properties.Name -notcontains $field) { throw "Missing status field: $field" }
  }

  if ($status.blockers -notcontains "api_base_not_configured") { throw "Missing API base should be a blocker." }
  if ($status.blockers -notcontains "worker_token_file_missing") { throw "Missing worker token file should be a blocker." }
  if ([bool]$status.codex_available -or [bool]$status.matlab_available) { throw "Forced missing Codex/MATLAB detection failed." }
  if ($status.warnings -notcontains "codex_missing_codex_templates_disabled") { throw "Missing Codex should be a warning." }
  if ($status.warnings -notcontains "matlab_missing_matlab_templates_disabled") { throw "Missing MATLAB should be a warning." }
  if ([string]$status.readiness_status -ne "blocked") { throw "Missing config should not produce ready status." }

  $before = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  $previewRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-install-preview.ps1") -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  Assert-NoUnsafeText (($previewRaw | Out-String).Trim())
  $preview = (($previewRaw | Out-String).Trim() | ConvertFrom-Json)
  Assert-False $preview.would_mutate "install preview would_mutate"
  Assert-True $preview.apply_supported "install preview apply_supported"
  Assert-False $preview.task_claimed "install preview task_claimed"
  Assert-False $preview.codex_run_called "install preview codex_run_called"
  Assert-False $preview.matlab_run_called "install preview matlab_run_called"
  Assert-False $preview.arbitrary_shell_enabled "install preview arbitrary_shell_enabled"
  Assert-False $preview.worker_loop_started "install preview worker_loop_started"
  Assert-TokenPrintedFalse $preview
  $after = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  if ($before.Count -ne $after.Count) { throw "Install preview mutated temp home." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-status"
    schema = $status.schema
    readiness_status = $status.readiness_status
    preview_mutated = $false
    claim_enabled = $false
    execute_enabled = $false
    worker_loop_started = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 10 -Compress
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
