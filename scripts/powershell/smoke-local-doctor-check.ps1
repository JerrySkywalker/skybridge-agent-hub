. "$PSScriptRoot\smoke-productization-common.ps1"
$doctor = Invoke-JsonScript "skybridge-local-doctor.ps1" @("-Command", "check")
if ($doctor.schema -ne "skybridge.local_doctor_report.v1") { throw "schema mismatch" }
Assert-True $doctor.checks.bootstrap_complete "bootstrap_complete"
Assert-True $doctor.checks.productization_rc "productization_rc"
Assert-False $doctor.token_printed "token_printed"
Complete-Smoke "local-doctor-check"
