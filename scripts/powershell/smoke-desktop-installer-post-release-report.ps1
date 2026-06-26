. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-post-release-smoke.ps1" @(
  "-Command", "safe-summary",
  "-WriteReport"
)

Assert-True $result.ok "desktop_installer_post_release_report_ok"
Assert-FileExists $result.report_json_path
Assert-FileExists $result.report_markdown_path
$jsonText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_json_path)
$mdText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_markdown_path)
Assert-NoUnsafeText $jsonText
Assert-NoUnsafeText $mdText
Assert-False $result.release_created "release_created"
Assert-False $result.release_updated "release_updated"
Assert-False $result.asset_uploaded "asset_uploaded"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-post-release-report"
