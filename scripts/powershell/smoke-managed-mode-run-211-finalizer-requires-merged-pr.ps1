. "$PSScriptRoot/smoke-managed-mode-run-common.ps1"

$stateDir = Join-Path ([System.IO.Path]::GetTempPath()) ("skybridge-run-211-finalizer-unmerged-" + [Guid]::NewGuid().ToString("n"))
try {
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  [pscustomobject]@{ ok = $true; schema = "skybridge.managed_mode_run_apply_result.v1"; run_id = "managed-mode-run-211"; codex_execution_count = 1; pr_created = $true; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/999999"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-result.json") -Encoding UTF8
  [pscustomobject]@{ schema = "skybridge.managed_mode_run_record.v1"; run_id = "managed-mode-run-211"; codex_execution_count = 1; pr_count = 1; pr_url = "https://github.com/JerrySkywalker/skybridge-agent-hub/pull/999999"; token_printed = $false } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $stateDir "run-evidence.json") -Encoding UTF8
  $result = Invoke-ManagedModeRunJson "run-finalizer-apply" @("-ManagedModeRunId", "managed-mode-run-211", "-StateDir", $stateDir, "-TargetPath", "docs/managed-mode-v0-repeatability-check.md")
  if ($result.ok -ne $false) { throw "Finalizer must refuse unmerged run-211 PR." }
  if ($result.final_state -notin @("held_waiting_human_pr_review", "finalizer_blocked")) { throw "Unexpected run-211 finalizer refusal state." }
  Write-ManagedModeRunSmokeResult "managed-mode-run-211-finalizer-requires-merged-pr"
} finally {
  Remove-Item -LiteralPath $stateDir -Recurse -Force -ErrorAction SilentlyContinue
}
