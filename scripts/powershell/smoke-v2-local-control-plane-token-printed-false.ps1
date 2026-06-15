$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Invoke-SmokeJson "skybridge-authenticated-session-rehearsal.ps1" @("-Command", "report") | Out-Null
Invoke-SmokeJson "skybridge-auth-soak.ps1" @("-Command", "report") | Out-Null
Invoke-SmokeJson "skybridge-v2-local-control-plane-rc.ps1" @("-Command", "report") | Out-Null

$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($path in @(
  ".agent\tmp\local-auth\authenticated-session-rehearsal-report.json",
  ".agent\tmp\local-auth\auth-soak-report.json",
  ".agent\tmp\local-auth\v2-local-control-plane-rc-report.json",
  ".agent\tmp\local-auth\v2-local-control-plane-rc-report.md"
)) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
  if (Test-UnsafeText $text) { throw "Unsafe text in $path" }
}

Write-Host "[smoke-v2-local-control-plane-token-printed-false] ok"
