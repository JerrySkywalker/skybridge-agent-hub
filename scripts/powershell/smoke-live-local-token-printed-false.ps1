$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Invoke-SmokeJson "skybridge-live-local-server.ps1" @("-Command", "report") | Out-Null
$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($path in @(
  ".agent\tmp\live-local\live-local-server-report.json",
  ".agent\tmp\live-local\live-local-server-report.md",
  ".agent\tmp\live-local\live-local-e2e-report.json",
  ".agent\tmp\live-local\v2.1-live-local-rc-report.json",
  ".agent\tmp\live-local\v2.1-live-local-rc-report.md"
)) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
  if (Test-UnsafeText $text) { throw "Unsafe text in $path" }
}
Write-Host "[smoke-live-local-token-printed-false] ok"
