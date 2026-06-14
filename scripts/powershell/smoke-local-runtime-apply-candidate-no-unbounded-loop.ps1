. "$PSScriptRoot\smoke-productization-common.ps1"
$candidate = Invoke-JsonScript "skybridge-local-runtime.ps1" @("-Command", "apply-candidate")
Assert-False $candidate.starts_unbounded_loop "starts_unbounded_loop"
foreach ($component in @($candidate.components)) { Assert-True $component.bounded "component.bounded" }
Complete-Smoke "local-runtime-apply-candidate-no-unbounded-loop"
