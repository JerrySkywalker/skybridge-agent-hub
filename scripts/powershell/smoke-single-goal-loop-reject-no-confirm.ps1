. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-goal-loop.ps1" @("-Command", "apply-once", "-Fixture")
if (@($result.blockers) -notcontains "missing_exact_confirmation") { throw "Missing confirmation should block apply." }
Assert-False $result.apply_confirmed "apply_confirmed"
Assert-False $result.task_claimed "task_claimed"
Assert-False $result.execution_started "execution_started"
Assert-False $result.evidence_attached "evidence_attached"
Assert-TokenPrintedFalse $result

Complete-Smoke "single-goal-loop-reject-no-confirm"
