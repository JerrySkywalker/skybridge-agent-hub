[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff"
$reportPath = Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json"
if (-not (Test-Path -LiteralPath $reportPath -PathType Leaf)) {
  Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-local-diff-preview", "-OutputDir", $outputDir) | Out-Null
}

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$safety = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-safety.json") | ConvertFrom-Json

Assert-False $report.branch_pushed "branch_pushed"
Assert-False $report.commit_created "commit_created"
Assert-False $report.pr_created "pr_created"
Assert-False $safety.safety_flags.branch_pushed "safety branch_pushed"
Assert-False $safety.safety_flags.commit_created "safety commit_created"
if (Test-Path -LiteralPath (Join-Path $RepoRoot "$outputDir/workspace/.git")) {
  throw "Preview must not create a Git workspace."
}
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-no-push"
