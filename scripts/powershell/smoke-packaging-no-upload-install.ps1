. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "safe-summary")
Assert-False $summary.upload_planned "upload_planned"
Assert-False $summary.install_planned "install_planned"
Assert-False $summary.github_release_planned "github_release_planned"
Complete-Smoke "packaging-no-upload-install"
