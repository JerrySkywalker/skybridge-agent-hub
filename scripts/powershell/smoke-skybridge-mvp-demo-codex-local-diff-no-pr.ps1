[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff-no-pr"
$resolvedOutputDir = Join-Path $RepoRoot $outputDir
$tmpRoot = Join-Path $RepoRoot ".agent/tmp"
if (-not ([System.IO.Path]::GetFullPath($resolvedOutputDir).StartsWith([System.IO.Path]::GetFullPath($tmpRoot)))) {
  throw "Refusing to clean output outside .agent/tmp."
}
if (Test-Path -LiteralPath $resolvedOutputDir) {
  Remove-Item -LiteralPath $resolvedOutputDir -Recurse -Force
}
$reportPath = Join-Path $RepoRoot "$outputDir/codex-local-diff-report.json"
Invoke-JsonScript "skybridge-mvp-demo.ps1" @("-Mode", "codex-local-diff-preview", "-OutputDir", $outputDir) | Out-Null

$report = Get-Content -Raw -LiteralPath $reportPath | ConvertFrom-Json
$safety = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-local-diff-safety.json") | ConvertFrom-Json

Assert-False $report.pr_created "pr_created"
Assert-False $report.demo_pr_311_modified "demo_pr_311_modified"
Assert-False $report.tui_created_branch "tui_created_branch"
Assert-False $report.tui_created_pr "tui_created_pr"
Assert-False $report.auto_merge_enabled "auto_merge_enabled"
Assert-False $report.release_created "release_created"
Assert-False $report.tag_created "tag_created"
Assert-False $report.asset_uploaded "asset_uploaded"
Assert-False $safety.safety_flags.pr_created "safety pr_created"
Assert-False $safety.safety_flags.demo_pr_311_modified "safety demo_pr_311_modified"
Assert-TokenPrintedFalse $report

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-no-pr"
