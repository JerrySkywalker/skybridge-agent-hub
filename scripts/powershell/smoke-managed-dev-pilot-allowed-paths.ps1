. "$PSScriptRoot\smoke-productization-common.ps1"

$confirm = "I_UNDERSTAND_APPLY_ONE_MANAGED_DEV_CHANGE_ONLY"
$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "apply-fixture",
  "-Fixture",
  "-Confirm", $confirm
)
if (@($result.blockers).Count -ne 0) { throw "Allowed path fixture should not be blocked." }
foreach ($file in @($result.changed_files)) {
  $allowed = $false
  foreach ($prefix in @($result.allowed_paths)) {
    if ($file -eq $prefix.TrimEnd("/") -or $file.StartsWith($prefix)) { $allowed = $true }
  }
  if (-not $allowed) { throw "Changed file was not allowed: $file" }
}
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-pilot-allowed-paths"
