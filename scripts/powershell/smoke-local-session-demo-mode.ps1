. "$PSScriptRoot\smoke-productization-common.ps1"
$demo = Invoke-JsonScript "skybridge-local-session.ps1" @("-Command", "demo")
if ($demo.mode -ne "operator_demo_fixture") { throw "Expected operator demo fixture." }
Assert-False $demo.starts_worker "starts_worker"
Assert-False $demo.executes_workunit "executes_workunit"
Assert-False $demo.creates_task "creates_task"
Assert-False $demo.mutates_system "mutates_system"
Assert-TokenPrintedFalse $demo
Complete-Smoke "local-session-demo-mode"
