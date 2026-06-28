. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-e2e-handoff.ps1" @(
  "-Command", "audit"
)

Assert-True $result.required_docs_present "required_docs_present"
Assert-True $result.required_scripts_present "required_scripts_present"
Assert-True $result.required_smokes_present "required_smokes_present"

$manualScripts = @($result.capability_matrix | ForEach-Object { [string]$_.manual_script })
foreach ($script in $manualScripts) {
  Assert-FileExists $script
}

foreach ($script in @(
  "scripts/powershell/skybridge-managed-dev-e2e-handoff.ps1",
  "scripts/powershell/smoke-managed-dev-e2e-handoff-status.ps1",
  "scripts/powershell/smoke-managed-dev-e2e-handoff-audit.ps1",
  "scripts/powershell/smoke-managed-dev-e2e-freeze-checklist.ps1",
  "scripts/powershell/smoke-managed-dev-e2e-required-artifacts.ps1",
  "scripts/powershell/smoke-managed-dev-e2e-no-mutation.ps1",
  "scripts/powershell/smoke-manual-managed-dev-e2e-handoff-fixture.ps1"
)) {
  Assert-FileExists $script
}

Assert-TokenPrintedFalse $result
Complete-Smoke "managed-dev-e2e-required-artifacts"
