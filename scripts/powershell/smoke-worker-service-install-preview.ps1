[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$tempHome = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-worker-service-install-preview-" + [Guid]::NewGuid().ToString("n"))
New-Item -ItemType Directory -Path $tempHome | Out-Null

try {
  $before = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  $raw = & (Join-Path $PSScriptRoot "skybridge-worker-service-install.ps1") -Command preview -HomeRoot $tempHome -RepoRoot $RepoRoot -Json
  $text = ($raw | Out-String).Trim()
  Assert-NoUnsafeText $text
  $preview = $text | ConvertFrom-Json

  if ([string]$preview.schema -ne "skybridge.local_worker_service_install.v1") { throw "Unexpected install preview schema." }
  if ([string]$preview.mode -ne "preview") { throw "Install preview mode mismatch." }
  Assert-True $preview.ok "install preview ok"
  Assert-False $preview.would_mutate "install preview would_mutate"
  Assert-False $preview.did_mutate "install preview did_mutate"
  Assert-True $preview.confirmation_required "install preview confirmation_required"
  Assert-False $preview.claim_enabled "install preview claim_enabled"
  Assert-False $preview.execute_enabled "install preview execute_enabled"
  Assert-False $preview.template_runner_enabled "install preview template_runner_enabled"
  Assert-False $preview.worker_loop_started "install preview worker_loop_started"
  Assert-False $preview.codex_run_called "install preview codex_run_called"
  Assert-False $preview.matlab_run_called "install preview matlab_run_called"
  Assert-False $preview.arbitrary_shell_enabled "install preview arbitrary_shell_enabled"
  Assert-TokenPrintedFalse $preview

  if (@($preview.status.blockers) -notcontains "api_base_not_configured") { throw "Missing API base should be a blocker." }
  if (@($preview.status.blockers) -notcontains "worker_token_file_missing") { throw "Missing token file should be a blocker." }

  $after = @(Get-ChildItem -LiteralPath $tempHome -Recurse -Force)
  if ($before.Count -ne $after.Count) { throw "Install preview mutated temp home." }

  [pscustomobject]@{
    ok = $true
    smoke = "worker-service-install-preview"
    schema = $preview.schema
    preview_mutated = $false
    missing_api_base_blocker = $true
    missing_token_file_blocker = $true
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
