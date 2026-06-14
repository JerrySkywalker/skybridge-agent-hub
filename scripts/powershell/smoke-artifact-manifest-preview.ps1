. "$PSScriptRoot\smoke-productization-common.ps1"
$manifest = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "artifact-manifest-preview")
if ($manifest.schema -ne "skybridge.release_artifact_manifest.v1") { throw "Unexpected manifest schema." }
foreach ($artifact in $manifest.artifacts) {
  Assert-False $artifact.upload_planned "artifact upload_planned"
  Assert-False $artifact.install_planned "artifact install_planned"
  Assert-False $artifact.checksum_present "artifact checksum_present"
}
Complete-Smoke "artifact-manifest-preview"
