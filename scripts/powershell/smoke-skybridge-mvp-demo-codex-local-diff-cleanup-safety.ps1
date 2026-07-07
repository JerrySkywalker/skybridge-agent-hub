[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-diff/cleanup-safety-smoke"
$resolvedOutputDir = Join-Path $RepoRoot $outputDir
if (Test-Path -LiteralPath $resolvedOutputDir) {
  Remove-Item -LiteralPath $resolvedOutputDir -Recurse -Force
}

$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-local-diff-cleanup-safety",
  "-OutputDir", $outputDir
)

if ([string]$result.schema -ne "skybridge.mvp_demo.codex_local_diff.cleanup_safety_fixture.v1") { throw "Unexpected cleanup safety schema." }
if ([string]$result.demo_result -ne "pass") { throw "Cleanup safety fixture did not pass." }
Assert-True $result.outside_agent_tmp_rejected "outside_agent_tmp_rejected"
Assert-True $result.repo_root_rejected "repo_root_rejected"
Assert-True $result.confirmation_required "confirmation_required"
Assert-False $result.codex_called "codex_called"
Assert-False $result.pr_created "pr_created"
Assert-False $result.branch_pushed "branch_pushed"
Assert-False $result.commit_created "commit_created"
Assert-TokenPrintedFalse $result

foreach ($file in @(
  "codex-local-diff-cleanup-safety-fixture-report.json",
  "codex-local-diff-cleanup-safety-outside.json",
  "codex-local-diff-cleanup-safety-repo-root.json",
  "codex-local-diff-cleanup-safety-auth.json"
)) {
  Assert-FileExists "$outputDir/$file"
}

Complete-Smoke "skybridge-mvp-demo-codex-local-diff-cleanup-safety"
