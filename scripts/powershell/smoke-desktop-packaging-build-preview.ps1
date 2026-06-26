. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-desktop-packaging-readiness.ps1" @("-Command", "build-preview")

Assert-True $result.ok "desktop_packaging_build_preview_ok"
Assert-True $result.build_preview_ok "build_preview_ok"
Assert-False $result.local_build_attempted "local_build_attempted"
Assert-False $result.release_created "release_created"
Assert-False $result.tag_created "tag_created"
Assert-False $result.installer_uploaded "installer_uploaded"
Assert-False $result.binary_uploaded "binary_uploaded"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "desktop-packaging-build-preview"
