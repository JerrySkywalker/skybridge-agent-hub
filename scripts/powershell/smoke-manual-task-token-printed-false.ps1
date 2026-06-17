$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "smoke-installer-promotion-common.ps1")

Invoke-SmokeJson "skybridge-manual-task-queue.ps1" @("-Command", "report") | Out-Null
$root = Resolve-Path "$PSScriptRoot\..\.."
foreach ($path in @(
  ".agent\tmp\manual-task\manual-task-queue.json",
  ".agent\tmp\manual-task\manual-task-report.json",
  ".agent\tmp\manual-task\manual-task-report.md"
)) {
  $text = Get-Content -Raw -LiteralPath (Join-Path $root $path)
  if (Test-UnsafeText $text) { throw "Unsafe text in $path" }
}
Write-Host "[smoke-manual-task-token-printed-false] ok"
