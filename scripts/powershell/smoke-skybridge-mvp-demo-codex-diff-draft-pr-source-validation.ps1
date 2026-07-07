[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$fixtureDir = Join-Path $RepoRoot ".agent/tmp/skybridge-mvp-codex-draft-pr-source-fixture"
$validOut = ".agent/tmp/skybridge-mvp-codex-draft-pr-source-fixture/valid-out"
$invalidOut = ".agent/tmp/skybridge-mvp-codex-draft-pr-source-fixture/invalid-out"
New-Item -ItemType Directory -Force -Path $fixtureDir | Out-Null

$reportPath = Join-Path $fixtureDir "source-report.json"
$patchPath = Join-Path $fixtureDir "source.patch"
$artifactPath = Join-Path $fixtureDir "worktree/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $artifactPath) | Out-Null

$sourceReport = [ordered]@{
  demo_result = "pass"
  codex_called = $true
  codex_call_count = 1
  codex_exit_code = 0
  changed_files = @("docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md")
  docs_only_allowlist_passed = $true
  diff_patch_non_empty = $true
  pr_created = $false
  branch_pushed = $false
  commit_created = $false
  token_printed = $false
}
$sourceReport | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
"diff --git a/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md b/docs/product/MG372D_CODEX_LOCAL_DIFF_ARTIFACT.md" | Set-Content -LiteralPath $patchPath -Encoding UTF8
"# MG372D fixture artifact" | Set-Content -LiteralPath $artifactPath -Encoding UTF8

$valid = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-diff-draft-pr-preview",
  "-OutputDir", $validOut,
  "-SourceReportPath", (Resolve-Path -LiteralPath $reportPath).Path,
  "-SourcePatchPath", (Resolve-Path -LiteralPath $patchPath).Path,
  "-SourceArtifactPath", (Resolve-Path -LiteralPath $artifactPath).Path
)
if ([string]$valid.validation_status -ne "preview_passed") { throw "Valid source fixture did not pass preview." }

$invalidPatchPath = Join-Path $fixtureDir "missing.patch"
$invalid = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-diff-draft-pr-preview",
  "-OutputDir", $invalidOut,
  "-SourceReportPath", (Resolve-Path -LiteralPath $reportPath).Path,
  "-SourcePatchPath", $invalidPatchPath,
  "-SourceArtifactPath", (Resolve-Path -LiteralPath $artifactPath).Path
)
if ([string]$invalid.validation_status -ne "preview_blocked") { throw "Invalid source fixture did not block preview." }
if (@($invalid.blockers) -notcontains "source_patch_missing") { throw "Missing patch blocker was not reported." }
Assert-False $invalid.pr_created "invalid.pr_created"
Assert-False $invalid.branch_pushed "invalid.branch_pushed"
Assert-False $invalid.commit_created "invalid.commit_created"
Assert-False $invalid.codex_called_in_mg372e2 "invalid.codex_called_in_mg372e2"
Assert-TokenPrintedFalse $valid
Assert-TokenPrintedFalse $invalid

Complete-Smoke "skybridge-mvp-demo-codex-diff-draft-pr-source-validation"
