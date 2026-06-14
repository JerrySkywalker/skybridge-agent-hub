. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-desktop-package-candidate.ps1" @("-Command", "report")
Assert-FileExists ".agent/tmp/packaging-preview/desktop-package-candidate.json"
Assert-False $candidate.verification.upload_planned "upload_planned"
Assert-False $candidate.verification.install_planned "install_planned"
Assert-TokenPrintedFalse $candidate
Complete-Smoke "desktop-package-candidate"
