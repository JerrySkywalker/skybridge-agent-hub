. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "plan")
foreach ($component in $plan.components) {
  Assert-False $component.starts_unbounded_loop "starts_unbounded_loop"
}
Complete-Smoke "local-runtime-no-unbounded-loop"
