[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-identity-preview-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-identity.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ([string]$missing.schema -ne "skybridge.worker_identity.v1") { throw "Unexpected worker identity schema." }
  if ($missing.ok -ne $false) { throw "Missing worker id preview should fail closed." }
  if ($missing.blockers -notcontains "worker_id_not_configured") { throw "Missing worker id blocker not reported." }
  Assert-False $missing.would_mutate "missing preview would_mutate"
  Assert-False $missing.did_mutate "missing preview did_mutate"
  Assert-TokenPrintedFalse $missing

  $before = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  $previewRaw = & (Join-Path $PSScriptRoot "skybridge-worker-identity.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
  $previewText = ($previewRaw | Out-String).Trim()
  Assert-NoUnsafeText $previewText
  $preview = $previewText | ConvertFrom-Json
  Assert-True $preview.ok "worker identity explicit preview ok"
  Assert-False $preview.would_mutate "identity preview would_mutate"
  Assert-False $preview.did_mutate "identity preview did_mutate"
  if ([string]$preview.worker_id -ne "jerry-win-local-01") { throw "Explicit worker id not returned." }
  if ($preview.capabilities -notcontains "windows" -or $preview.capabilities -notcontains "powershell") { throw "Expected safe base capabilities." }
  Assert-False $preview.claim_enabled "identity preview claim_enabled"
  Assert-False $preview.execute_enabled "identity preview execute_enabled"
  Assert-False $preview.worker_loop_started "identity preview worker_loop_started"
  Assert-False $preview.codex_run_called "identity preview codex_run_called"
  Assert-False $preview.matlab_run_called "identity preview matlab_run_called"
  Assert-TokenPrintedFalse $preview
  $after = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  if ($before.Count -ne $after.Count) { throw "Worker identity preview mutated temp home." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-identity-preview"
    schema = $preview.schema
    missing_worker_id_blocked = $true
    explicit_worker_id_preview_ok = $true
    worker_id = $preview.worker_id
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
