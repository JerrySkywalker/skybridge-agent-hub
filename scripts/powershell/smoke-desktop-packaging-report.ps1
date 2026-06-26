. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-packaging-readiness.ps1" @("-Command", "audit", "-WriteReport")

Assert-True $result.ok "desktop_packaging_report_ok"
if (-not $result.report_markdown_path) { throw "Missing report_markdown_path." }
if (-not $result.report_json_path) { throw "Missing report_json_path." }
Assert-FileExists $result.report_markdown_path
Assert-FileExists $result.report_json_path

$markdown = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_markdown_path)
$json = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_json_path)
Assert-NoUnsafeText $markdown
Assert-NoUnsafeText $json
Assert-False $result.release_created "release_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-packaging-report"
