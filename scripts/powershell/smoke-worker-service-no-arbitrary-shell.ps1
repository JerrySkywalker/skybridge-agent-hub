[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$script = Get-Content -Raw -LiteralPath (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1")
if ($script -match "\[string\]\$CommandToRun|\[scriptblock\]|Invoke-Expression|cmd\.exe|Start-Process") {
  throw "Worker service exposes an arbitrary shell or process boundary."
}
$status = & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repoRoot "scripts\powershell\skybridge-worker-service.ps1") -Command status -Json | ConvertFrom-Json
if ([bool]$status.worker_service.capability_matrix.arbitrary_shell) { throw "Capability matrix allows arbitrary_shell." }

[pscustomobject]@{
  ok = $true
  smoke = "worker-service-no-arbitrary-shell"
  arbitrary_shell = $false
  token_printed = $false
} | ConvertTo-Json -Depth 10 -Compress
