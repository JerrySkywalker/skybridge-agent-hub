. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-manual-install-preview.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $plan
Assert-True $plan.preview_only "preview_only"
Assert-False $plan.install_allowed "install_allowed"
Assert-FileExists ".agent/tmp/portable-package/manual-install-preview.json"
Complete-Smoke "manual-install-preview"
