[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\smoke-productization-common.ps1"

$outputDir = ".agent/tmp/skybridge-mvp-codex-draft-pr"
$result = Invoke-JsonScript "skybridge-mvp-demo.ps1" @(
  "-Mode", "codex-diff-draft-pr-preview",
  "-OutputDir", $outputDir
)
$provider = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-provider-report.json") | ConvertFrom-Json
$safety = Get-Content -Raw -LiteralPath (Join-Path $RepoRoot "$outputDir/codex-draft-pr-safety.json") | ConvertFrom-Json

Assert-False $result.codex_called_in_mg372e2 "result.codex_called_in_mg372e2"
Assert-False $provider.codex_called "provider.codex_called"
Assert-False $safety.safety_flags.codex_called_in_mg372e2 "safety.codex_called_in_mg372e2"
Assert-True $result.source_codex_called "result.source_codex_called"
if ([int]$result.source_codex_call_count -ne 1) { throw "source_codex_call_count must be 1." }
Assert-TokenPrintedFalse $result

Complete-Smoke "skybridge-mvp-demo-codex-diff-draft-pr-no-codex"
