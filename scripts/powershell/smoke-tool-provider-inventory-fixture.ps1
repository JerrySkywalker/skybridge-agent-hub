. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "inventory", "-Fixture")

if ($result.schema -ne "skybridge.tool_provider.v1") { throw "Unexpected schema." }
if (@($result.providers).Count -lt 5) { throw "Expected provider records." }
if (@($result.tools | Where-Object { $_.tool_id -eq "codex" }).Count -ne 1) { throw "Codex tool missing." }
if (@($result.tools | Where-Object { $_.tool_id -eq "matlab" }).Count -ne 1) { throw "MATLAB tool missing." }
if (@($result.tools | Where-Object { $_.tool_id -eq "mcp" -and $_.status -eq "future" }).Count -ne 1) { throw "MCP future tool missing." }
Assert-False $result.execution_allowed "execution_allowed"
Assert-False $result.codex_run_called "codex_run_called"
Assert-False $result.matlab_run_called "matlab_run_called"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-inventory-fixture"
