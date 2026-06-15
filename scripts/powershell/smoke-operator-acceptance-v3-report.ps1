. "$PSScriptRoot\smoke-productization-common.ps1"
$report = Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "v3-report")
Assert-TokenPrintedFalse $report
Assert-True ($report.release_workflow_side_effect_guard_status -in @("passed", "blocked")) "release guard status"
Assert-True ($report.installer_candidate_status -in @("passed", "blocked", "preview")) "installer status"
Assert-FileExists ".agent/tmp/operator-acceptance/operator-acceptance-v3-report.json"
Complete-Smoke "operator-acceptance-v3-report"
