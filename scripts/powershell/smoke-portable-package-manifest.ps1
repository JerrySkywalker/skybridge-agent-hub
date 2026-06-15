. "$PSScriptRoot\smoke-productization-common.ps1"
$manifest = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "manifest")
Assert-TokenPrintedFalse $manifest
if ($manifest.schema -ne "skybridge.portable_package_manifest.v1") { throw "Unexpected manifest schema." }
Assert-False $manifest.install_allowed "install_allowed"
Assert-False $manifest.github_release_allowed "github_release_allowed"
Assert-NoUnsafeText ($manifest | ConvertTo-Json -Depth 40)
Complete-Smoke "portable-package-manifest"
