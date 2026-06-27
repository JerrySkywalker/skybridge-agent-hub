. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-launch-diagnostics.ps1" @("-Command", "status", "-WriteReport")

Assert-True $result.ok "desktop_launch_report_ok"
Assert-False $result.launch_attempted "launch_attempted"
Assert-FileExists $result.report_json_path
Assert-FileExists $result.report_markdown_path

$jsonText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_json_path)
$mdText = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_markdown_path)
Assert-NoUnsafeText $jsonText
Assert-NoUnsafeText $mdText
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-launch-report"
