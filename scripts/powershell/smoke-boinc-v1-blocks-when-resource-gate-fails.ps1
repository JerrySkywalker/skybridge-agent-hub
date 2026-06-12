. "$PSScriptRoot/smoke-boinc-v1-common.ps1"
$gate = Invoke-BoincV1PreviewJson -Command "apply-gate" -SimulateResourceGateFail
Assert-False ([bool]$gate.resource_gate.can_run_one_at_a_time) "Simulated resource gate must fail."
Assert-True ($gate.blockers -contains "blocked_by_resource_gate") "Apply gate must include resource gate blocker."
Assert-False ([bool]$gate.apply_enabled) "Apply must remain disabled."
Write-SmokeResult "boinc-v1-blocks-when-resource-gate-fails"
