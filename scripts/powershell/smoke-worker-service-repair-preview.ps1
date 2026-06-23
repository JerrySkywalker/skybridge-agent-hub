[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-service-repair-preview-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $before = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-repair.ps1") -Command repair-preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $preview = $text | ConvertFrom-Json
  if ([string]$preview.schema -ne "skybridge.local_worker_service_repair.v1") { throw "Unexpected repair preview schema." }
  Assert-True $preview.ok "repair preview ok"
  Assert-False $preview.would_mutate "repair preview would_mutate"
  Assert-False $preview.did_mutate "repair preview did_mutate"
  Assert-TokenPrintedFalse $preview

  $after = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  if ($before.Count -ne $after.Count) { throw "Repair preview mutated temp home." }

  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-repair.ps1") -Command repair-apply -HomeRoot $tempHome -RepoRoot $RepoRoot -Fixture -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ($missing.ok -ne $false) { throw "Repair apply without confirmation should be rejected." }
  if ([string]$missing.review_reason -ne "missing_exact_confirmation") { throw "Repair apply rejection reason mismatch." }
  Assert-False $missing.did_mutate "repair missing confirmation did_mutate"
  Assert-TokenPrintedFalse $missing

  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-repair-preview"
    schema = $preview.schema
    preview_mutated = $false
    missing_confirmation_rejected = $true
    claim_enabled = $false
    execute_enabled = $false
    worker_loop_started = $false
    codex_run_called = $false
    matlab_run_called = $false
    arbitrary_shell_enabled = $false
    token_printed = $false
  } | ConvertTo-Json -Depth 8 -Compress
} finally {
  Remove-Item -LiteralPath $tempHome -Recurse -Force -ErrorAction SilentlyContinue
}
