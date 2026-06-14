. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-packaging-preview.ps1" @("-Command", "release-artifact-preview")
Assert-False $report.uploads_artifacts "uploads_artifacts"
Assert-False $report.creates_github_release "creates_github_release"
Assert-TokenPrintedFalse $report
Complete-Smoke "packaging-preview-no-upload"
