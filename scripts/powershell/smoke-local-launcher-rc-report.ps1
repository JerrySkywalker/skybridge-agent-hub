. "$PSScriptRoot\smoke-productization-common.ps1"
$launcher = Invoke-JsonScript "skybridge-launcher.ps1" @("-Command", "report")
$supervisor = Invoke-JsonScript "skybridge-session-supervisor.ps1" @("-Command", "report")
$walkthrough = Invoke-JsonScript "skybridge-operator-walkthrough.ps1" @("-Command", "report")
foreach ($item in @($launcher, $supervisor, $walkthrough)) { Assert-TokenPrintedFalse $item }
Assert-FileExists ".agent/tmp/local-launcher/launcher-report.json"
Assert-FileExists ".agent/tmp/local-launcher/session-supervisor-report.json"
Assert-FileExists ".agent/tmp/local-launcher/operator-walkthrough-report.json"
Complete-Smoke "local-launcher-rc-report"
