[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-service-install-apply-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null
$confirmation = "I_UNDERSTAND_INSTALL_LOCAL_WORKER_SERVICE_NO_TASK_EXECUTION"

try {
  $missingRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-install.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -ApiBase "http://127.0.0.1:1" -WorkerId "mg330-fixture-worker" -Fixture -Json
  $missingText = ($missingRaw | Out-String).Trim()
  Assert-NoUnsafeText $missingText
  $missing = $missingText | ConvertFrom-Json
  if ($missing.ok -ne $false) { throw "Install apply without confirmation should be rejected." }
  if ([string]$missing.review_reason -ne "missing_exact_confirmation") { throw "Install apply rejection reason mismatch." }
  Assert-False $missing.did_mutate "missing confirmation did_mutate"
  Assert-TokenPrintedFalse $missing
  if (@(Get-ChildItem -LiteralPath $tempHome -Recurse -Force).Count -ne 0) { throw "Rejected install apply mutated temp home." }

  $applyRaw = & (Join-Path $PSScriptRoot "skybridge-worker-service-install.ps1") -Command apply -HomeRoot $tempHome -RepoRoot $RepoRoot -ApiBase "http://127.0.0.1:1" -WorkerId "mg330-fixture-worker" -Fixture -Confirm -ConfirmationText $confirmation -Json
  $applyText = ($applyRaw | Out-String).Trim()
  Assert-NoUnsafeText $applyText
  if ($applyText -match "fixture-local-auth-value") { throw "Fixture token value was printed." }
  $apply = $applyText | ConvertFrom-Json
  if ([string]$apply.schema -ne "skybridge.local_worker_service_install.v1") { throw "Unexpected install apply schema." }
  Assert-True $apply.ok "install apply ok"
  Assert-True $apply.did_mutate "install apply did_mutate"
  Assert-True $apply.status.service_installed "install status service_installed"
  Assert-False $apply.status.service_running "install status service_running"
  Assert-True $apply.status.api_base_configured "install status api_base_configured"
  Assert-True $apply.status.token_file_present "install status token_file_present"
  Assert-True $apply.status.repo_root_detected "install status repo_root_detected"
  Assert-False $apply.claim_enabled "install apply claim_enabled"
  Assert-False $apply.execute_enabled "install apply execute_enabled"
  Assert-False $apply.template_runner_enabled "install apply template_runner_enabled"
  Assert-False $apply.worker_loop_started "install apply worker_loop_started"
  Assert-False $apply.codex_run_called "install apply codex_run_called"
  Assert-False $apply.matlab_run_called "install apply matlab_run_called"
  Assert-False $apply.arbitrary_shell_enabled "install apply arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $apply

  foreach ($file in Get-ChildItem -LiteralPath $tempHome -Recurse -Force -File) {
    if (-not $file.FullName.StartsWith($tempHome, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Install fixture wrote outside temp home."
    }
  }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-install-apply-fixture"
    schema = $apply.schema
    missing_confirmation_rejected = $true
    service_installed = $apply.status.service_installed
    service_running = $apply.status.service_running
    api_base_configured = $apply.status.api_base_configured
    token_file_present = $apply.status.token_file_present
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
