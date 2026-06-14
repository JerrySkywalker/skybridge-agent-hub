. "$PSScriptRoot\smoke-productization-common.ps1"
$runtime = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "apply-candidate")
$artifact = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "artifact-verify")
$config = Invoke-JsonScript "skybridge-local-config.ps1" @("-Command", "report")
$rc = Invoke-JsonScript "skybridge-local-productization-rc.ps1" @("-Command", "report")
foreach ($item in @($runtime, $artifact, $config, $rc)) { Assert-TokenPrintedFalse $item }
foreach ($path in @(
  ".agent/tmp/local-runtime/local-runtime-apply-candidate.json",
  ".agent/tmp/packaging-preview/desktop-artifact-verification.json",
  ".agent/tmp/product-readiness/local-config-validation-report.json",
  ".agent/tmp/product-readiness/local-productization-rc-report.json"
)) {
  if (Test-Path -LiteralPath (Join-Path $RepoRoot $path)) {
    Assert-NoUnsafeText (Get-Content -Raw -LiteralPath (Join-Path $RepoRoot $path))
  }
}
Complete-Smoke "local-productization-rc-token-printed-false"
