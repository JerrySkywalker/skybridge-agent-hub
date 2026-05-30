[CmdletBinding()]
param([int]$Port = 0, [switch]$Json)
$args = @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "smoke-status-fixture.ps1"), "-Scenario", "recent-tasks", "-Port", [string]$Port)
if ($Json) { $args += "-Json" }
& pwsh @args
exit $LASTEXITCODE
