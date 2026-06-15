[CmdletBinding()] param()
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
$scripts = @(
  @("skybridge-installer-promotion.ps1", @("-Command", "safe-summary")),
  @("skybridge-release-candidate-artifact.ps1", @("-Command", "safe-summary")),
  @("skybridge-long-soak.ps1", @("-Command", "safe-summary")),
  @("skybridge-channel-manifest.ps1", @("-Command", "safe-summary")),
  @("skybridge-host-mutation-gate.ps1", @("-Command", "safe-summary")),
  @("skybridge-installer-safety-interlock.ps1", @("-Command", "safe-summary")),
  @("skybridge-release-walkthrough.ps1", @("-Command", "safe-summary")),
  @("skybridge-installer-promotion-rc.ps1", @("-Command", "safe-summary"))
)
foreach ($item in $scripts) {
  $r = Invoke-SmokeJson $item[0] $item[1]
  if ($r.token_printed -ne $false) { throw "$($item[0]) token_printed not false." }
}
Write-Host "[smoke-installer-promotion-273-280-token-printed-false] ok"
