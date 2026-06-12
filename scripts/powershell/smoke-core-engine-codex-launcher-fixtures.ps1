$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot "lib/Skybridge.CodexExecutor.psm1") -Force
$exe = Invoke-SkybridgeCodexFixture -Prompt "fixture prompt" -FixtureCommands @("C:/tools/codex.exe")
$cmd = Invoke-SkybridgeCodexFixture -Prompt "fixture prompt" -FixtureCommands @("C:/tools/codex.cmd")
$ps1 = Invoke-SkybridgeCodexFixture -Prompt "fixture prompt" -FixtureCommands @("C:/tools/codex.ps1")
if ($exe.resolved.launcher_kind -ne "exe" -or $cmd.resolved.launcher_kind -ne "cmd" -or $ps1.resolved.launcher_kind -ne "ps1") { throw "launcher classification failed" }
if ($exe.execution_invoked -ne $false) { throw "fixture must not invoke execution" }
[pscustomobject]@{ ok = $true; scenario = "core-engine-codex-launcher-fixtures"; token_printed = $false } | ConvertTo-Json -Compress
