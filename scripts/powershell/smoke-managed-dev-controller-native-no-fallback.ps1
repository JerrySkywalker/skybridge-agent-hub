. "$PSScriptRoot\smoke-productization-common.ps1"

$source = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "scripts/powershell/skybridge-managed-dev-pilot.ps1")
if ($source -match 'manual_fallback_used\s*=\s*\$true') {
  throw "Controller must not report manual_fallback_used=true."
}

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "preview",
  "-Fixture",
  "-BranchName", "codex/mg360-controller-native-managed-dev-pilot-pr"
)

Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-False $result.auto_merge_enabled "auto_merge_enabled"
Assert-False $result.merge_performed "merge_performed"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-controller-native-no-fallback"
