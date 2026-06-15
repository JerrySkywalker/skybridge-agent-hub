. "$PSScriptRoot\smoke-productization-common.ps1"
$gate = Invoke-JsonScript "skybridge-release-workflow-guard.ps1" @("-Command", "tag-safety-gate")
Assert-TokenPrintedFalse $gate
Assert-True ($gate.gate -in @("passed", "blocked")) "gate classified"
Assert-False $gate.manual_github_release_creation_allowed "manual_github_release_creation_allowed"
Complete-Smoke "tag-safety-gate"
