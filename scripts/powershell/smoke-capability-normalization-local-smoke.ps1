[CmdletBinding()]
param([switch]$Json)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "skybridge-worker-api.ps1")

$task = [pscustomobject]@{
  task_id = "smoke-local-smoke-capability-normalization"
  task_type = "local-smoke"
  title = "Add worker readiness smoke"
  body = "Create a read-only local smoke that checks git, gh, node and PowerShell availability without printing token values."
  required_capabilities = @("powershell", "windows")
  expected_files = @("scripts/powershell/smoke-worker-loop-status.ps1")
  allowed_paths = @("scripts/powershell/smoke-worker-loop-status.ps1")
}

$normalized = Normalize-SkyBridgeTaskCapabilities -Task $task
foreach ($capability in @("powershell", "windows")) {
  if (@($normalized.original_required_capabilities) -notcontains $capability) {
    throw "Expected original local-smoke capability $capability to be preserved."
  }
}
foreach ($capability in @("codex", "powershell", "windows")) {
  if (@($normalized.normalized_required_capabilities) -notcontains $capability) {
    throw "Expected local-smoke normalization to include $capability."
  }
}
if (-not $normalized.safe_local_smoke) { throw "Expected local-smoke task to pass safe-local-smoke gate." }
if ($normalized.capability_normalization_reason -ne "safe_local_smoke_expected_files_use_codex_powershell_windows") { throw "Unexpected normalization reason." }

$summary = [pscustomobject]@{
  ok = $true
  original_required_capabilities = @($normalized.original_required_capabilities)
  normalized_required_capabilities = @($normalized.normalized_required_capabilities)
  reason = $normalized.capability_normalization_reason
  safe_local_smoke = $normalized.safe_local_smoke
  token_printed = $false
}
if ($Json) { $summary | ConvertTo-Json -Depth 8 -Compress } else { $summary | Format-List }
