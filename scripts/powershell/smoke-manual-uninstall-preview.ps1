. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-manual-uninstall-preview.ps1" @("-Command", "report")
Assert-TokenPrintedFalse $plan
Assert-True $plan.preview_only "preview_only"
Assert-False $plan.uninstall_allowed "uninstall_allowed"
Assert-FileExists ".agent/tmp/portable-package/manual-uninstall-preview.json"
Complete-Smoke "manual-uninstall-preview"
