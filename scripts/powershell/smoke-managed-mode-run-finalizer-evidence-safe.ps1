. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-finalizer-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  [pscustomobject]@{ ok = $true; schema = "skybridge.managed_mode_run_apply_result.v1"; run_id = "managed-mode-run-209"; workunit_id = "managed-mode-run-209-workunit-001"; task_id = "managed-mode-run-209-task-001"; worker_id = "laptop-zenbookduo"; codex_execution_count = 1; pr_created = $true; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; changed_files = @("docs/managed-mode-repeatability-orientation.md"); resource_gate_pass = $true; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-result.json") -Encoding UTF8
  [pscustomobject]@{ schema = "skybridge.managed_mode_run_record.v1"; run_id = "managed-mode-run-209"; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; resource_gate_pass = $true; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-evidence.json") -Encoding UTF8
  $result = Invoke-ManagedModeRunJson "run-finalizer-apply" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr")
  if ($result.final_state -ne "managed_mode_run_209_completed") { throw "Expected completed finalizer evidence." }
  Assert-ManagedModeRunSafeJson $result
  Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-evidence-safe"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
