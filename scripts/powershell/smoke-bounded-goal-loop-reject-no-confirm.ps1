. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-bounded-goal-loop.ps1" @(
  "-Command", "apply-one",
  "-Fixture",
  "-Scenario", "ready-step"
)
Assert-False $result.apply_confirmed "apply_confirmed"
Assert-False $result.action_performed "action_performed"
if (-not (@($result.blockers) -contains "missing_bounded_loop_confirmation")) { throw "Missing confirmation blocker not reported." }
Assert-False $result.task_created "task_created"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "bounded-goal-loop-reject-no-confirm"
