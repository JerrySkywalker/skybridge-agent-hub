. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-finalizer-rerun-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  [pscustomobject]@{ ok = $true; schema = "skybridge.managed_mode_run_apply_result.v1"; run_id = "managed-mode-run-209"; codex_execution_count = 1; pr_created = $true; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-result.json") -Encoding UTF8
  [pscustomobject]@{ schema = "skybridge.managed_mode_run_record.v1"; run_id = "managed-mode-run-209"; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-evidence.json") -Encoding UTF8
  Invoke-ManagedModeRunJson "run-finalizer-apply" @("-StateDir", $stateDir, "-TargetPath", "docs/managed-mode-repeatability-orientation.md", "-SimulateFinalizerMergedPr") | Out-Null
  $second = Invoke-ManagedModeRunJson "run-finalizer-apply" @("-StateDir", $stateDir, "-TargetPath", "docs/managed-mode-repeatability-orientation.md", "-SimulateFinalizerMergedPr")
  if ($second.ok -ne $false -or $second.blockers -notcontains "managed_mode_run_209_already_completed") { throw "Expected duplicate finalizer refusal." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-refuses-rerun"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
