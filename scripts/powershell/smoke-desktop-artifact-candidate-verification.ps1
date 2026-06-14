. "$PSScriptRoot\smoke-productization-common.ps1"
$verification = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "artifact-verify")
if ($verification.schema -ne "skybridge.desktop_artifact_verification.v1") { throw "schema mismatch" }
Assert-True $verification.ok "ok"
Assert-True $verification.repo_local_only "repo_local_only"
Assert-False $verification.upload_planned "upload_planned"
Assert-False $verification.install_planned "install_planned"
Complete-Smoke "desktop-artifact-candidate-verification"
