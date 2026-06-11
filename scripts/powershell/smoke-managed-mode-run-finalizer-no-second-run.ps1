. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-finalizer-second-" + [Guid]::NewGuid().ToString("n"))
$target = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path "docs/managed-mode-repeatability-orientation.md"
try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  "fixture" | Set-Content -LiteralPath $target -Encoding UTF8
  [pscustomobject]@{ ok = $true; schema = "skybridge.managed_mode_run_apply_result.v1"; run_id = "managed-mode-run-209"; codex_execution_count = 1; pr_created = $true; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-result.json") -Encoding UTF8
  [pscustomobject]@{ schema = "skybridge.managed_mode_run_record.v1"; run_id = "managed-mode-run-209"; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/209"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-evidence.json") -Encoding UTF8
  $preview = Invoke-ManagedModeRunJson "run-finalizer-preview" @("-StateDir", $stateDir, "-SimulateFinalizerMergedPr", "-SimulateFinalizerSecondRun")
  if ($preview.blockers -notcontains "second_run_detected") { throw "Expected second run blocker." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-finalizer-no-second-run"
} finally {
  Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
