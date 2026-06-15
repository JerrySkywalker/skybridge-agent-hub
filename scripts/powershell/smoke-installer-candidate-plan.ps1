. "$PSScriptRoot\smoke-productization-common.ps1"
$plan = Invoke-JsonScript "skybridge-installer-candidate.ps1" @("-Command", "plan")
Assert-TokenPrintedFalse $plan
Assert-True $plan.build_writes_only_agent_tmp "build_writes_only_agent_tmp"
Assert-False $plan.host_mutation_allowed "host_mutation_allowed"
Assert-False $plan.github_release_allowed "github_release_allowed"
Complete-Smoke "installer-candidate-plan"
