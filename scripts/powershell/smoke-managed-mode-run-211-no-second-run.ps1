. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-211-rerun-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  [pscustomobject]@{ ok = $true; schema = "skybridge.managed_mode_run_apply_result.v1"; run_id = "managed-mode-run-211"; codex_execution_count = 1; pr_created = $true; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/999999"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-result.json") -Encoding UTF8
  [pscustomobject]@{ schema = "skybridge.managed_mode_run_record.v1"; run_id = "managed-mode-run-211"; codex_execution_count = 1; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/999999"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-evidence.json") -Encoding UTF8
  $second = Invoke-ManagedModeRunJson "run-finalizer-preview" @("-ManagedModeRunId", "managed-mode-run-211", "-StateDir", $stateDir, "-TargetPath", "docs/managed-mode-v0-operator-checklist.md", "-SimulateFinalizerMergedPr", "-SimulateFinalizerSecondRun")
  if ($second.can_finalize -ne $false -or $second.blockers -notcontains "second_run_detected") { throw "Expected duplicate run-211 blocker." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-211-no-second-run"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
