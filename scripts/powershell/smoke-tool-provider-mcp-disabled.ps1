. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "mcp", "-Fixture")
$provider = @($result.providers | Where-Object { $_.provider_id -eq "mcp-disabled" } | Select-Object -First 1)[0]
$tool = @($result.tools | Where-Object { $_.tool_id -eq "mcp" } | Select-Object -First 1)[0]

if ($provider.provider_type -ne "mcp") { throw "MCP provider type mismatch." }
if ($provider.status -ne "future") { throw "MCP provider should be future." }
if ($tool.status -ne "future") { throw "MCP tool should be future." }
Assert-False $provider.execution_enabled "mcp execution_enabled"
Assert-False $result.mcp_run_called "mcp_run_called"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-mcp-disabled"
