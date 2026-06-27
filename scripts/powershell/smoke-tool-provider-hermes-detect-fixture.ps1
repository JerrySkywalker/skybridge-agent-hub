. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "hermes", "-Fixture")
$provider = @($result.providers | Where-Object { $_.provider_id -eq "hermes-optional" } | Select-Object -First 1)[0]
$tool = @($result.tools | Where-Object { $_.tool_id -eq "hermes" } | Select-Object -First 1)[0]

if ($provider.provider_type -ne "hermes") { throw "Hermes provider type mismatch." }
if ($provider.status -ne "available") { throw "Hermes fixture should be configured." }
if ($tool.status -ne "detected") { throw "Hermes fixture tool should be detected." }
Assert-False $provider.execution_enabled "hermes execution_enabled"
Assert-False $result.hermes_run_called "hermes_run_called"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-hermes-detect-fixture"
