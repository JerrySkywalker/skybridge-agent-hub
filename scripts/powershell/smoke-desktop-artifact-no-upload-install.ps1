. "$PSScriptRoot\smoke-productization-common.ps1"
$summary = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "artifact-safe-summary")
Assert-False $summary.upload_planned "upload_planned"
Assert-False $summary.install_planned "install_planned"
Assert-False $summary.github_release_planned "github_release_planned"
Assert-False $summary.signing_planned "signing_planned"
Complete-Smoke "desktop-artifact-no-upload-install"
