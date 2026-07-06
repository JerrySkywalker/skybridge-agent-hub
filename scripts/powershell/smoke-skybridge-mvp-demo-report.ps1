[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-demo"
$reportPath = Join-Path $RepoRoot "$outputDir/mvp-demo-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "local-safe", "-UseTempDatabase", "-OutputDir", $outputDir) | Out-Null
}

$status = Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "status", "-OutputDir", $outputDir)
$report = Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "report", "-OutputDir", $outputDir)

Assert-True $status.report_found "status.report_found"
Assert-True $report.report_found "report.report_found"
if ([string]$status.demo_result -notin @("pass", "partial")) { throw "Status did not report pass or partial." }
if ([string]$report.summary -notmatch "task_completed=True") { throw "Report summary missing task completion." }
Assert-TokenPrintedFalse $status
Assert-TokenPrintedFalse $report

Assert-FileExists "$outputDir/mvp-demo-report.json"
Assert-FileExists "$outputDir/mvp-demo-report.md"
Assert-NoUnsafeText (Get-Content -Raw -LiteralPath $reportPath)

Complete-Smoke "skybridge-mvp-demo-report"
