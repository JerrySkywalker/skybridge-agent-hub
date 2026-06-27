. "$PSScriptRoot\smoke-productization-common.ps1"

$raw = & pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "manual-tool-provider-check.ps1") -Fixture -Json
if ($LASTEXITCODE -ne 0) { throw "manual-tool-provider-check failed." }
$text = ($raw | Out-String).Trim()
Assert-NoUnsafeText $text
$result = $text | ConvertFrom-Json

if ($result.milestone -ne "M1: Tool Provider Inventory Manual Check") { throw "Unexpected milestone." }
if ($result.direct_provider_detected -ne "yes") { throw "Fixture direct provider should be yes." }
if ($result.codex_detected -ne "yes") { throw "Fixture Codex should be yes." }
if ($result.mcp_enabled -ne "no / future") { throw "MCP should remain future." }
if ($result.execution_performed -ne "no") { throw "Manual check should not execute." }
Assert-False $result.execution_started "execution_started"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.worker_loop_started "worker_loop_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "manual-tool-provider-check-fixture"
