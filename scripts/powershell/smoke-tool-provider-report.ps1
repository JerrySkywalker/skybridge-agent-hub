. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/tool-provider-smoke"
$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "audit", "-Fixture", "-WriteReport", "-OutputDir", $outputDir)

if (-not $result.report_json_path) { throw "Report JSON path missing." }
if (-not $result.report_markdown_path) { throw "Report Markdown path missing." }
Assert-FileExists $result.report_json_path
Assert-FileExists $result.report_markdown_path
Assert-NoUnsafeText (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_json_path))
Assert-NoUnsafeText (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $result.report_markdown_path))
Assert-False $result.execution_allowed "execution_allowed"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-report"
