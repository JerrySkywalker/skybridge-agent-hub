. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-staging.ps1" @(
  "-Command", "audit",
  "-OutputDir", ".agent/tmp/desktop-installer-staging-report",
  "-WriteReport"
)

Assert-True $result.ok "desktop_installer_staging_report_ok"
Assert-FileExists $result.manifest_path
Assert-FileExists $result.report_path
$manifestText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.manifest_path)
$reportText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_path)
Assert-NoUnsafeText $manifestText
Assert-NoUnsafeText $reportText
Assert-False $result.release_created "release_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-staging-report"
