. "$PSScriptRoot\smoke-productization-common.ps1"
$result = Invoke-JsonScript "skybridge-operator-acceptance.ps1" @("-Command", "report")
if ($result.status -ne "passed") { throw "Operator acceptance report did not pass." }
if ($result.clean_room_rehearsal_status -ne "passed") { throw "Clean-room status not passed." }
if ($result.artifact_integrity_status -ne "passed") { throw "Artifact integrity status not passed." }
if ($result.fixture_soak_status -ne "passed") { throw "Fixture soak status not passed." }
Assert-FileExists ".agent/tmp/operator-acceptance/operator-acceptance-report.json"
Assert-FileExists ".agent/tmp/operator-acceptance/operator-acceptance-report.md"
Assert-TokenPrintedFalse $result
Complete-Smoke "smoke-operator-acceptance-report"
