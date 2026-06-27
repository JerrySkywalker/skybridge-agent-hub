param(
  [switch]$Json,
  [switch]$WriteReport,
  [string]$HermesEnvFile = "",
  [switch]$Fixture
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
$inventoryScript = Join-Path $PSScriptRoot "skybridge-tool-provider.ps1"
$argsList = @("-Command", "inventory")
if ($HermesEnvFile) { $argsList += @("-HermesEnvFile", $HermesEnvFile) }
if ($WriteReport) { $argsList += "-WriteReport" }
if ($Fixture) { $argsList += "-Fixture" }
$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File $inventoryScript @argsList -Json
if ($LASTEXITCODE -ne 0) { throw "tool provider inventory failed" }
$inventory = (($raw | Out-String).Trim() | ConvertFrom-Json)

function Get-ProviderStatus([string]$ProviderId) {
  $provider = @($inventory.providers | Where-Object { $_.provider_id -eq $ProviderId } | Select-Object -First 1)
  if (@($provider).Count -eq 0) { return "missing" }
  [string]$provider[0].status
}

function Get-ToolStatus([string]$ToolId) {
  $tool = @($inventory.tools | Where-Object { $_.tool_id -eq $ToolId } | Select-Object -First 1)
  if (@($tool).Count -eq 0) { return "missing" }
  [string]$tool[0].status
}

$directStatus = Get-ProviderStatus "direct-local"
$hermesStatus = Get-ProviderStatus "hermes-optional"
$mcpStatus = Get-ProviderStatus "mcp-disabled"
$codexStatus = Get-ToolStatus "codex"
$matlabStatus = Get-ToolStatus "matlab"
$summary = [pscustomobject]@{
  schema = "skybridge.tool_provider_manual_check.v1"
  milestone = "M1: Tool Provider Inventory Manual Check"
  direct_provider_detected = if ($directStatus -eq "available") { "yes" } elseif ($directStatus -eq "warning") { "warning" } else { "no" }
  codex_detected = if ($codexStatus -eq "detected") { "yes" } else { "no" }
  matlab_detected = if ($matlabStatus -eq "detected") { "yes" } else { "no" }
  hermes_configured = if ($hermesStatus -eq "available") { "yes" } elseif ($hermesStatus -eq "warning") { "warning" } else { "no" }
  mcp_enabled = "no / future"
  execution_performed = "no"
  report_json_path = if ($inventory.PSObject.Properties["report_json_path"]) { $inventory.report_json_path } else { "" }
  report_markdown_path = if ($inventory.PSObject.Properties["report_markdown_path"]) { $inventory.report_markdown_path } else { "" }
  task_created = $false
  task_claimed = $false
  execution_started = $false
  codex_run_called = $false
  matlab_run_called = $false
  hermes_run_called = $false
  mcp_run_called = $false
  worker_loop_started = $false
  project_control_unpaused = $false
  token_printed = $false
}

if ($Json) {
  $summary | ConvertTo-Json -Depth 8
} else {
  "M1: Tool Provider Inventory Manual Check"
  "Direct provider detected: $($summary.direct_provider_detected)"
  "Codex detected: $($summary.codex_detected)"
  "MATLAB detected: $($summary.matlab_detected)"
  "Hermes configured: $($summary.hermes_configured)"
  "MCP enabled: $($summary.mcp_enabled)"
  "Execution performed: no"
  "token_printed=false"
}
