. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/packaging-preview/desktop-artifact-candidate.json"
Assert-FileExists ".agent/tmp/packaging-preview/desktop-artifact-verification.json"
Assert-FileExists ".agent/tmp/packaging-preview/desktop-artifact-manifest.md"
Assert-TokenPrintedFalse $candidate
Complete-Smoke "desktop-artifact-manifest"
