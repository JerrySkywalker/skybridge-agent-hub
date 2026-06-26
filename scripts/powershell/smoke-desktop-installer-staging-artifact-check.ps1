. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-installer-staging.ps1" @("-Command", "artifact-check")

if ($result.status -notin @("pass", "warning")) { throw "Unexpected status: $($result.status)" }
Assert-True $result.ok "desktop_installer_staging_artifact_check_ok"
Assert-False $result.build_attempted "build_attempted"
Assert-False $result.package_attempted "package_attempted"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.release_created "release_created"
Assert-False $result.github_release_updated "github_release_updated"
Assert-False $result.tag_created "tag_created"
Assert-False $result.tag_moved "tag_moved"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-installer-staging-artifact-check"
