. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "status",
  "-Fixture"
)

Assert-True $result.git_available "git_available"
if ([string]::IsNullOrWhiteSpace([string]$result.git_detection_method)) { throw "git_detection_method missing." }
if ([string]$result.git_blocker -ne "") { throw "git_blocker should be empty when git is detected." }
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-git-provider-detect"
