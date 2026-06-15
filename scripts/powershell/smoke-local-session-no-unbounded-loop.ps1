. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "start", "-Apply", "-Profile", "full-local-preview")
Assert-True $plan.preview_only "missing -Bounded must stay preview"
Assert-False $plan.starts_unbounded_loop "starts_unbounded_loop"
Assert-TokenPrintedFalse $plan
Complete-Smoke "local-session-no-unbounded-loop"
