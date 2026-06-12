$ErrorActionPreference = "Stop"
$modules = @(
  "Skybridge.Core",
  "Skybridge.CodexExecutor",
  "Skybridge.ResourceGate",
  "Skybridge.WorkunitRegistry",
  "Skybridge.EvidenceStore",
  "Skybridge.PrPackager",
  "Skybridge.Finalizer",
  "Skybridge.QueuePolicy",
  "Skybridge.SafetyScanner",
  "Skybridge.SmokeHarness"
)
foreach ($module in $modules) {
  Import-Module (Join-Path $PSScriptRoot "lib/$module.psm1") -Force
}
[pscustomobject]@{ ok = $true; scenario = "core-engine-module-imports"; modules = $modules; token_printed = $false } | ConvertTo-Json -Compress
