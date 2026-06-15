. "$PSScriptRoot\smoke-productization-common.ps1"
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "skybridge-local-doctor.ps1") -Command report -Json
if ($LASTEXITCODE -ne 0) { throw "doctor report failed" }
Assert-NoUnsafeText (($raw | Out-String).Trim())
$doctor = (($raw | Out-String).Trim() | ConvertFrom-Json)
Assert-TokenPrintedFalse $doctor
Complete-Smoke "local-doctor-no-env-dump"
