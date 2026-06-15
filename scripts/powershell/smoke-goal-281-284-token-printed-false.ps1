$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")
Invoke-SmokeJson "skybridge-local-auth.ps1" @("-Command", "report") | Out-Null
Invoke-SmokeJson "skybridge-attestation-preview.ps1" @("-Command", "report") | Out-Null
Invoke-SmokeJson "skybridge-sbom-preview.ps1" @("-Command", "report") | Out-Null
Invoke-SmokeJson "skybridge-host-consent-preview.ps1" @("-Command", "report") | Out-Null
$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($path in @(
  ".agent\tmp\local-auth\local-auth-report.json",
  ".agent\tmp\attestation\attestation-preview-report.json",
  ".agent\tmp\sbom\sbom-preview.json",
  ".agent\tmp\host-consent\host-consent-preview-report.json"
)) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
  if (Test-UnsafeText $text) { throw "Unsafe text in $path" }
}
foreach ($path in @("apps\web\src\main.tsx", "apps\desktop\src\main.tsx")) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
  if ($text -match '"token_printed"\s*:\s*true|token_printed:\s*true|token_printed\s*=\s*\$true') {
    throw "token_printed=true found in $path"
  }
}
Write-Host "[smoke-goal-281-284-token-printed-false] ok"
