$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "report") | Out-Null
$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($relative in @(
  ".agent\tmp\manual-task\server-hermes-provider-report.json",
  ".agent\tmp\manual-task\server-hermes-provider-report.md",
  ".agent\tmp\manual-task\server-hermes-preview-report.json",
  ".agent\tmp\manual-task\server-hermes-live-optin-report.json"
)) {
  $path = Join-Path $root $relative
  if (Test-Path -LiteralPath $path) {
    $text = Get-Content -Raw -LiteralPath $path
    if (Test-UnsafeText $text) { throw "Unsafe token/report text in $relative." }
    if ($text -match 'token_printed"\s*:\s*true|token_printed=true') { throw "token_printed true in $relative." }
  }
}
Write-Host "[smoke-manual-task-server-hermes-token-printed-false] ok"
