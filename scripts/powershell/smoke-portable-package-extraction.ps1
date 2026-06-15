. "$PSScriptRoot\smoke-productization-common.ps1"
$smoke = Invoke-JsonScript "skybridge-portable-package.ps1" @("-Command", "extract-smoke")
Assert-TokenPrintedFalse $smoke
Assert-True $smoke.ok "extract smoke ok"
Assert-True $smoke.skybridge_ps1_exists "skybridge.ps1 exists"
Assert-True $smoke.launcher_exists "launcher exists"
Assert-False $smoke.starts_codex_worker "starts_codex_worker"
Assert-False $smoke.runs_workunit_apply "runs_workunit_apply"
Assert-False $smoke.runs_queue_apply "runs_queue_apply"
Complete-Smoke "portable-package-extraction"
