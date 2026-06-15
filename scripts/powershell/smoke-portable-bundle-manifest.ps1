. "$PSScriptRoot\smoke-productization-common.ps1"
$manifest = Invoke-JsonScript "skybridge-portable-bundle.ps1" @("-Command", "manifest")
Assert-TokenPrintedFalse $manifest
Assert-True $manifest.docs_present "docs_present"
Assert-True $manifest.scripts_present "scripts_present"
Assert-True $manifest.fixture_present "fixture_present"
Assert-False $manifest.install_allowed "install_allowed"
Complete-Smoke "portable-bundle-manifest"
