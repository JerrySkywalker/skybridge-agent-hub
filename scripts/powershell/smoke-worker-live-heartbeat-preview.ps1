[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-live-heartbeat-preview-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ([string]$missing.schema -ne "skybridge.worker_live_heartbeat.v1") { throw "Unexpected live heartbeat schema." }
  if ($missing.ok -ne $false) { throw "Missing live heartbeat config should fail closed." }
  if ($missing.blockers -notcontains "worker_id_not_configured") { throw "Missing worker id blocker not reported." }
  Assert-False $missing.would_mutate_server "missing preview would_mutate_server"
  Assert-False $missing.server_mutation_performed "missing preview server_mutation_performed"
  Assert-TokenPrintedFalse $missing

  $before = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  $previewRaw = & (Join-Path $PSScriptRoot "skybridge-worker-live-heartbeat.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
  $previewText = ($previewRaw | Out-String).Trim()
  Assert-NoUnsafeText $previewText
  $preview = $previewText | ConvertFrom-Json
  if ($preview.ok -ne $false) { throw "Live heartbeat preview without API/token should remain blocked." }
  if ($preview.blockers -notcontains "api_base_not_configured") { throw "Missing API base blocker not reported." }
  if ($preview.blockers -notcontains "worker_token_file_missing") { throw "Missing worker token file blocker not reported." }
  Assert-False $preview.would_mutate_server "live preview would_mutate_server"
  Assert-False $preview.server_mutation_performed "live preview server_mutation_performed"
  Assert-False $preview.claim_enabled "live preview claim_enabled"
  Assert-False $preview.execute_enabled "live preview execute_enabled"
  Assert-False $preview.worker_loop_started "live preview worker_loop_started"
  Assert-False $preview.codex_run_called "live preview codex_run_called"
  Assert-False $preview.matlab_run_called "live preview matlab_run_called"
  Assert-TokenPrintedFalse $preview
  $after = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  if ($before.Count -ne $after.Count) { throw "Live heartbeat preview mutated temp home." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-live-heartbeat-preview"
    schema = $preview.schema
    missing_worker_id_blocked = $true
    missing_api_base_blocked = $true
    missing_token_file_blocked = $true
    preview_mutated = $false
    claim_enabled = $false
    execute_enabled = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
