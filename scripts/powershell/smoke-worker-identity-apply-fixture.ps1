[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-identity-apply-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
$confirmation = "I_UNDERSTAND_CONFIGURE_LOCAL_WORKER_IDENTITY_NO_TASK_EXECUTION"

try {
  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-identity.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ($missing.ok -ne $false) { throw "Identity apply without confirmation should be rejected." }
  if ([string]$missing.review_reason -ne "missing_exact_confirmation") { throw "Identity missing confirmation reason mismatch." }
  Assert-False $missing.did_mutate "identity missing confirmation did_mutate"
  Assert-TokenPrintedFalse $missing
  if (@(Get-ChildItem -LiteralPath $tempHome -Recurse -Force).Count -ne 0) { throw "Rejected identity apply mutated temp home." }

  $applyRaw = & (Join-Path $PSScriptRoot "skybridge-worker-identity.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -WorkerId "jerry-win-local-01" -WorkerName "Jerry Windows Local Worker" -Provider "local-windows" -Confirm -ConfirmationText $confirmation -Json
  $applyText = ($applyRaw | Out-String).Trim()
  Assert-NoUnsafeText $applyText
  $apply = $applyText | ConvertFrom-Json
  Assert-True $apply.ok "identity apply ok"
  Assert-True $apply.did_mutate "identity apply did_mutate"
  if ([string]$apply.worker_id -ne "jerry-win-local-01") { throw "Identity apply worker id mismatch." }
  Assert-False $apply.claim_enabled "identity apply claim_enabled"
  Assert-False $apply.execute_enabled "identity apply execute_enabled"
  Assert-False $apply.worker_loop_started "identity apply worker_loop_started"
  Assert-False $apply.codex_run_called "identity apply codex_run_called"
  Assert-False $apply.matlab_run_called "identity apply matlab_run_called"
  Assert-False $apply.arbitrary_shell_enabled "identity apply arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $apply

  $workerConfig = Join-Path $tempHome ".skybridge\worker.env.ps1"
  if (-not (Test-Path -LiteralPath $workerConfig -PathType Leaf)) { throw "Worker identity config was not written." }
  $configText = Get-Content -Raw -LiteralPath $workerConfig
  Assert-NoUnsafeText $configText
  foreach ($needle in @("SKYBRIDGE_WORKER_ID", "jerry-win-local-01", "SKYBRIDGE_WORKER_NAME", "Jerry Windows Local Worker", "SKYBRIDGE_WORKER_PROVIDER", "local-windows")) {
    if ($configText -notmatch [regex]::Escape($needle)) { throw "Worker identity config missing $needle" }
  }
  foreach ($forbidden in @("worker-token.txt", "SKYBRIDGE_API_BASE", "Authorization", "Bearer")) {
    if ($configText -match [regex]::Escape($forbidden)) { throw "Worker identity config included forbidden text $forbidden" }
  }

  $statusRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-status.ps1") -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $statusText = ($statusRaw | Out-String).Trim()
  Assert-NoUnsafeText $statusText
  $status = $statusText | ConvertFrom-Json
  Assert-True $status.worker_id_configured "status worker_id_configured after identity apply"
  if ([string]$status.worker_id -ne "jerry-win-local-01") { throw "Status worker id mismatch after identity apply." }
  if ([string]$status.worker_identity_status -ne "configured") { throw "Status worker identity not configured." }
  Assert-TokenPrintedFalse $status

  foreach ($file in Get-ChildItem -LiteralPath $tempHome -Recurse -Force -File) {
    if (-not $file.FullName.StartsWith($tempHome, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Identity fixture wrote outside temp home."
    }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-identity-apply-fixture"
    schema = $apply.schema
    missing_confirmation_rejected = $true
    worker_id = $apply.worker_id
    worker_id_configured = $status.worker_id_configured
    wrote_only_fixture_config = $true
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
