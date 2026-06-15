. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "plan")
Assert-TokenPrintedFalse $plan
Assert-True $plan.build_package_writes_only_agent_tmp "build_package_writes_only_agent_tmp"
Assert-False $plan.install_allowed "install_allowed"
Assert-False $plan.upload_allowed "upload_allowed"
Complete-Smoke "portable-package-plan"
