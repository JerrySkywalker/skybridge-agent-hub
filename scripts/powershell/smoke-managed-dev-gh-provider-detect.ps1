. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-managed-dev-pilot.ps1" @(
  "-Command", "status",
  "-Fixture"
)

Assert-True $result.gh_available "gh_available"
if ([string]::IsNullOrWhiteSpace([string]$result.gh_detection_method)) { throw "gh_detection_method missing." }
if ([string]$result.gh_blocker -ne "") { throw "gh_blocker should be empty when gh is detected." }
Assert-False $result.manual_fallback_used "manual_fallback_used"
Assert-TokenPrintedFalse $result

Complete-Smoke "managed-dev-gh-provider-detect"
