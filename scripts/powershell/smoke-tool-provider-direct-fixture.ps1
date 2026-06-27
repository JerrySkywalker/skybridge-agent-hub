. "$PSScriptRoot\smoke-productization-common.ps1"

$result = Invoke-JsonScript "skybridge-tool-provider.ps1" @("-Command", "direct", "-Fixture")
$direct = @($result.providers | Where-Object { $_.provider_id -eq "direct-local" } | Select-Object -First 1)[0]

if ($direct.provider_type -ne "direct") { throw "Direct provider type mismatch." }
if ($direct.status -ne "available") { throw "Direct provider should be available in fixture." }
foreach ($toolId in @("powershell", "git", "pnpm")) {
  $tool = @($result.tools | Where-Object { $_.tool_id -eq $toolId } | Select-Object -First 1)[0]
  if ($tool.status -ne "detected") { throw "$toolId should be detected in fixture." }
  Assert-False $tool.can_execute_now "$toolId can_execute_now"
}
Assert-False $direct.execution_enabled "direct execution_enabled"
Assert-False $result.execution_started "execution_started"
Assert-TokenPrintedFalse $result

Complete-Smoke "tool-provider-direct-fixture"
