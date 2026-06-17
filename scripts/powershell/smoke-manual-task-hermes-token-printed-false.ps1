$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

$root = Resolve-Path "$PSScriptRoot\..\.."
Invoke-SmokeJson "skybridge-manual-task-provider.ps1" @("-Command", "report") | Out-Null
$paths = @(
  ".agent\tmp\manual-task\manual-task-provider-report.json",
  ".agent\tmp\manual-task\manual-task-hermes-preview-report.json",
  ".agent\tmp\manual-task\manual-task-hermes-live-optin-report.json"
)
foreach ($relative in $paths) {
  $path = Join-Path $root $relative
  if (Test-Path -LiteralPath $path) {
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -match '"token_printed"\s*:\s*true|Authorization|Bearer\s+|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|BEGIN [A-Z ]*PRIVATE KEY') {
      throw "Unsafe token material found in $relative"
    }
  }
}
Write-Host "[smoke-manual-task-hermes-token-printed-false] ok"
