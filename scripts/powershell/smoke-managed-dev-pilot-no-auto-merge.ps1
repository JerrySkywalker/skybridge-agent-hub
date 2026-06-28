. "$PSScriptRoot\smoke-productization-common.ps1"

$scriptPath = Join-Path $RepoRoot "scripts/powershell/skybridge-managed-dev-pilot.ps1"
$source = Get-Content -Raw -LiteralPath $scriptPath
if ($source -match 'gh\s+pr\s+merge|--auto|auto_merge_enabled\s*=\s*\$true|merge_performed\s*=\s*\$true|release_created\s*=\s*\$true|tag_created\s*=\s*\$true|asset_uploaded\s*=\s*\$true|Start-Job|Register-ScheduledJob|Start-Service') {
  throw "Potential auto-merge, release, service, or unbounded pattern detected."
}
$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-Confirm", $confirm
)
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-no-auto-merge"
